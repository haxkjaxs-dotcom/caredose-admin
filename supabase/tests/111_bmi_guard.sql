-- integration.sql section 28: bmi_logs value checks, rate limit, own-patient-only insert.
begin;
insert into auth.users (id, email) values ('a1111000-0000-0000-0000-000000000001', 'bp@t'), ('a2111000-0000-0000-0000-000000000002', 'ba@t');
update profiles set is_active = true where id::text like 'a_111000%';
insert into user_roles (user_id, role) values ('a1111000-0000-0000-0000-000000000001', 'patient'), ('a2111000-0000-0000-0000-000000000002', 'admin');
insert into patients (id, full_name, user_id) values ('b1111000-0000-0000-0000-000000000001', 'P1', 'a1111000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1111000-0000-0000-0000-000000000001"}', true);
do $$
declare i int; ok boolean;
begin
  insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, 'normal');
  begin insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values ('b1111000-0000-0000-0000-000000000001', -5, 170, 20.8, 'x'); ok := true;
  exception when check_violation then ok := false; end;
  assert not ok, 'negative weight accepted';
  begin insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, repeat('x', 51)); ok := true;
  exception when check_violation then ok := false; end;
  assert not ok, 'long category accepted';
  begin insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category, calculated_at) values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, 'x', now() + interval '5 days'); ok := true;
  exception when sqlstate '22023' then ok := false; end;
  assert not ok, 'future date accepted';
  begin
    for i in 1..25 loop insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, 'normal'); end loop;
    ok := true;
  exception when sqlstate '54000' then ok := false; end;
  assert not ok, 'no rate limit';
end $$;
reset role;
-- the limit counts by the server's insert time, not calculated_at (which the app sends): back-dating every row must not get past it
delete from bmi_logs where patient_id = 'b1111000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1111000-0000-0000-0000-000000000001"}', true);
do $$
declare i int; ok boolean;
begin
  begin
    for i in 1..25 loop insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category, calculated_at)
      values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, 'normal', now() - interval '2 hours'); end loop;
    ok := true;
  exception when sqlstate '54000' then ok := false; end;
  assert not ok, 'back-dated rows got past the rate limit';
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2111000-0000-0000-0000-000000000002"}', true);
do $$
declare ok boolean;
begin
  begin insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values ('b1111000-0000-0000-0000-000000000001', 60, 170, 20.8, 'normal'); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'admin added bmi for a patient';
end $$;
reset role;
rollback;
