-- The harness applies security_fixes.sql a second time after integration.sql (it says "safe to re-run"), so this file proves
-- the two files converge: after the re-run claim_my_patient and save_my_profile still work for a patient, and the guard
-- still blocks a doctor from re-pointing patients.user_id.
-- Users: PU a patient who claims by phone, DOC an active doctor assigned to patient P2.
begin;

insert into auth.users (id, email, phone, phone_confirmed_at) values
  ('91000000-0000-0000-0000-000000000001', 'pu@t', '66855550001', now()),
  ('92000000-0000-0000-0000-000000000002', 'doc@t', '66855550002', now());
update profiles set is_active = true where id = '92000000-0000-0000-0000-000000000002';
insert into user_roles (user_id, role) values ('92000000-0000-0000-0000-000000000002', 'doctor');
insert into doctors (id, user_id, full_name) values ('93000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000002', 'Doc');
insert into patients (id, user_id, full_name, phone) values
  ('94000000-0000-0000-0000-000000000004', null, 'P1', '0855550001'),
  ('95000000-0000-0000-0000-000000000005', null, 'P2', '0855550009');
insert into patient_doctors (patient_id, doctor_id) values ('95000000-0000-0000-0000-000000000005', '93000000-0000-0000-0000-000000000003');

-- patient: claim, then fill in the profile (security definer functions must be able to write patients.user_id / the row)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  assert claim_my_patient() = '94000000-0000-0000-0000-000000000004', 'rerun: claim_my_patient failed';
  perform save_my_profile('เล่น', 'ชื่อ', 30, '{เบาหวาน}', '2026-11');
end $$;
reset role;
do $$
begin
  assert (select user_id from patients where id = '94000000-0000-0000-0000-000000000004') = '91000000-0000-0000-0000-000000000001', 'rerun: claim not stored';
  assert (select nickname from patients where id = '94000000-0000-0000-0000-000000000004') = 'เล่น', 'rerun: profile not stored';
end $$;

-- doctor: may edit the patient's age, may not re-point user_id (the guard is still in force)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"92000000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  update patients set age = 61 where id = '95000000-0000-0000-0000-000000000005';
  get diagnostics n = row_count;
  assert n = 1, 'rerun: doctor could not edit age';
  begin
    update patients set user_id = '92000000-0000-0000-0000-000000000002' where id = '95000000-0000-0000-0000-000000000005';
    raise exception 'rerun: doctor re-pointed patients.user_id';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select user_id from patients where id = '95000000-0000-0000-0000-000000000005') is null, 'rerun: user_id changed';
end $$;

rollback;
