-- integration.sql section 23: delete_patient removes the patient AND its login account (the Users page row), in one transaction.
-- An account that is also staff (doctor / admin) is kept; it only loses the patient role. Admin only.
-- Users: AD admin, DA doctor, PU patient of P1, PD doctor who still has patient row P2, PC relative of P9 who is also patient P4.
-- P3 has no account.
begin;
insert into auth.users (id, email) values
  ('a1021000-0000-0000-0000-000000000001', 'ad@t'), ('a1022000-0000-0000-0000-000000000002', 'da@t'),
  ('a1023000-0000-0000-0000-000000000003', 'pu@t'), ('a1024000-0000-0000-0000-000000000004', 'pd@t'),
  ('a1025000-0000-0000-0000-000000000005', 'pc@t');
update profiles set is_active = true where id::text like 'a102_000%';
insert into user_roles (user_id, role) values
  ('a1021000-0000-0000-0000-000000000001', 'admin'), ('a1022000-0000-0000-0000-000000000002', 'doctor'),
  ('a1023000-0000-0000-0000-000000000003', 'patient'),
  ('a1024000-0000-0000-0000-000000000004', 'doctor'), ('a1024000-0000-0000-0000-000000000004', 'patient'),
  ('a1025000-0000-0000-0000-000000000005', 'caregiver'), ('a1025000-0000-0000-0000-000000000005', 'patient');
insert into patients (id, user_id, full_name) values
  ('b1021000-0000-0000-0000-000000000001', 'a1023000-0000-0000-0000-000000000003', 'P1'),
  ('b1022000-0000-0000-0000-000000000002', 'a1024000-0000-0000-0000-000000000004', 'P2'),
  ('b1023000-0000-0000-0000-000000000003', null, 'P3'),
  ('b1024000-0000-0000-0000-000000000004', 'a1025000-0000-0000-0000-000000000005', 'P4'),
  ('b1029000-0000-0000-0000-000000000009', null, 'P9');
insert into caregivers (id, user_id, full_name) values ('c1025000-0000-0000-0000-000000000005', 'a1025000-0000-0000-0000-000000000005', 'PC');
insert into patient_caregivers (patient_id, caregiver_id, status) values
  ('b1029000-0000-0000-0000-000000000009', 'c1025000-0000-0000-0000-000000000005', 'confirmed');

-- a doctor may not delete patients
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1022000-0000-0000-0000-000000000002"}', true);
do $$
begin
  begin perform delete_patient('b1021000-0000-0000-0000-000000000001'); raise exception 'doctor deleted a patient';
  exception when insufficient_privilege then null; end;
end $$;

-- admin deletes all three
select set_config('request.jwt.claims', '{"sub":"a1021000-0000-0000-0000-000000000001"}', true);
select delete_patient('b1021000-0000-0000-0000-000000000001');
select delete_patient('b1022000-0000-0000-0000-000000000002');
select delete_patient('b1023000-0000-0000-0000-000000000003');
select delete_patient('b1024000-0000-0000-0000-000000000004');
do $$
begin
  begin perform delete_patient('b1023000-0000-0000-0000-000000000003'); raise exception 'deleted a missing patient';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from patients where id::text like 'b102%' and id <> 'b1029000-0000-0000-0000-000000000009'), 'patient rows left';
  -- patient-only account: gone with its profile and roles
  assert not exists (select 1 from auth.users where id = 'a1023000-0000-0000-0000-000000000003'), 'patient account left';
  assert not exists (select 1 from profiles where id = 'a1023000-0000-0000-0000-000000000003'), 'patient profile left';
  -- staff account: kept, only the patient role goes
  assert exists (select 1 from auth.users where id = 'a1024000-0000-0000-0000-000000000004'), 'staff account deleted';
  assert (select array_agg(role::text) from user_roles where user_id = 'a1024000-0000-0000-0000-000000000004') = array['doctor'], 'staff roles wrong';
  -- relative who was also a patient: keeps the login and the relative link, only the patient role goes
  assert exists (select 1 from auth.users where id = 'a1025000-0000-0000-0000-000000000005'), 'relative account deleted';
  assert (select array_agg(role::text) from user_roles where user_id = 'a1025000-0000-0000-0000-000000000005') = array['caregiver'], 'relative roles wrong';
  assert exists (select 1 from patient_caregivers where caregiver_id = 'c1025000-0000-0000-0000-000000000005'), 'relative link lost';
  assert (select count(*) from audit_logs where action = 'delete_patient') = 4, 'audit rows missing';
end $$;
rollback;
