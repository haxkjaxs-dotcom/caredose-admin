-- integration.sql section 25: only Admin deletes an appointment; a doctor still creates and edits them.
begin;
insert into auth.users (id, email) values ('a1102000-0000-0000-0000-000000000001', 'dd@t'), ('a2102000-0000-0000-0000-000000000002', 'ad@t');
update profiles set is_active = true where id::text like 'a_102000%';
insert into user_roles (user_id, role) values ('a1102000-0000-0000-0000-000000000001', 'doctor'), ('a2102000-0000-0000-0000-000000000002', 'admin');
insert into patients (id, full_name) values ('b1102000-0000-0000-0000-000000000001', 'P1');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1102000-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  insert into appointments (id, patient_id, appointment_at) values ('d1102000-0000-0000-0000-000000000001', 'b1102000-0000-0000-0000-000000000001', now());
  update appointments set place = 'x' where id = 'd1102000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor cannot edit an appointment';
  delete from appointments where id = 'd1102000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'doctor deleted an appointment';
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2102000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  delete from appointments where id = 'd1102000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'admin could not delete an appointment';
end $$;
reset role;
rollback;
