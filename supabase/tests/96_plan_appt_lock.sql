-- integration.sql section 14:
--  * medication_plans: over REST a non-admin cannot move a plan (and its adherence logs) to another patient, and created_by is
--    always the caller (it was free text, so the audit could name someone else as the author)
--  * appointments: the patient (appt_confirm) may only change status / note of their own appointment, not time, doctor or place
-- Users: AD admin, DA doctor of P1 and P2, PU patient P1. Plan1 belongs to P1. Appointment AP1 belongs to P1.
begin;

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'ad@t'), ('a2000000-0000-0000-0000-000000000002', 'da@t'),
  ('a5000000-0000-0000-0000-000000000005', 'pu@t');
update profiles set is_active = true;
insert into user_roles (user_id, role) values
  ('a1000000-0000-0000-0000-000000000001', 'admin'), ('a2000000-0000-0000-0000-000000000002', 'doctor'),
  ('a5000000-0000-0000-0000-000000000005', 'patient');
insert into patients (id, user_id, full_name) values
  ('b1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005', 'P1'),
  ('b2000000-0000-0000-0000-000000000002', null, 'P2');
insert into doctors (id, user_id, full_name) values ('d1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'DA');
insert into patient_doctors (patient_id, doctor_id) values
  ('b1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001'),
  ('b2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001');
insert into medicines (id, generic_name) values ('e1000000-0000-0000-0000-000000000001', 'M1');
insert into medication_plans (id, patient_id, medicine_id, dose, start_date) values
  ('f1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'D1', current_date);
insert into appointments (id, patient_id, doctor_id, appointment_at, place) values
  ('a9000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', '2030-01-01 09:00+07', 'OPD');

-- ===== 1) plans: doctor DA manages both patients =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  -- positive control: editing the plan itself still works
  update medication_plans set dose = 'D1x' where id = 'f1000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor could not edit a plan';
  begin
    update medication_plans set patient_id = 'b2000000-0000-0000-0000-000000000002' where id = 'f1000000-0000-0000-0000-000000000001';
    raise exception 'doctor moved a plan to another patient';
  exception when insufficient_privilege then null;
  end;
  begin
    update medication_plans set created_by = 'a1000000-0000-0000-0000-000000000001' where id = 'f1000000-0000-0000-0000-000000000001';
    raise exception 'doctor rewrote created_by';
  exception when insufficient_privilege then null;
  end;
  -- a direct insert naming someone else as author is stamped with the caller
  insert into medication_plans (id, patient_id, medicine_id, dose, start_date, created_by) values
    ('f3000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'D3', current_date,
     'a1000000-0000-0000-0000-000000000001');
end $$;
reset role;
do $$
begin
  assert (select created_by from medication_plans where id = 'f3000000-0000-0000-0000-000000000003') = 'a2000000-0000-0000-0000-000000000002',
         'insert kept a spoofed created_by';
  assert (select patient_id from medication_plans where id = 'f1000000-0000-0000-0000-000000000001') = 'b1000000-0000-0000-0000-000000000001', 'plan moved';
end $$;
-- save_plan (security definer) is unaffected and still records its caller
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1 tab', null,
                   current_date, null, null, array['08:00'], 'active');
  assert (select created_by from medication_plans where id = pid) = 'a2000000-0000-0000-0000-000000000002', 'save_plan created_by';
end $$;
-- admin may still move a plan (data correction)
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
update medication_plans set patient_id = 'b2000000-0000-0000-0000-000000000002' where id = 'f3000000-0000-0000-0000-000000000003';
reset role;
do $$
begin
  assert (select patient_id from medication_plans where id = 'f3000000-0000-0000-0000-000000000003') = 'b2000000-0000-0000-0000-000000000002',
         'admin could not move a plan';
end $$;

-- ===== 2) appointments: the patient confirms, but cannot rewrite the appointment =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-0000-0000-000000000005"}', true);
do $$
declare n int;
begin
  update appointments set status = 'done', note = 'มาแล้ว' where id = 'a9000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'patient could not confirm the appointment';
  begin
    update appointments set appointment_at = '2031-01-01 09:00+07' where id = 'a9000000-0000-0000-0000-000000000001';
    raise exception 'patient moved the appointment time';
  exception when insufficient_privilege then null;
  end;
  begin
    update appointments set doctor_id = null, place = 'x', reason = 'x' where id = 'a9000000-0000-0000-0000-000000000001';
    raise exception 'patient rewrote the appointment';
  exception when insufficient_privilege then null;
  end;
end $$;
-- the assigned doctor still edits everything
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  update appointments set appointment_at = '2030-02-01 09:00+07', place = 'ER' where id = 'a9000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor could not edit the appointment';
end $$;
reset role;
do $$
begin
  assert (select place from appointments where id = 'a9000000-0000-0000-0000-000000000001') = 'ER', 'appointment not updated';
  assert (select note from appointments where id = 'a9000000-0000-0000-0000-000000000001') = 'มาแล้ว', 'confirm note lost';
end $$;

rollback;
