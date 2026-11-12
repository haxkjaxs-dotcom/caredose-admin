-- integration.sql section 15: an active doctor sees and manages every patient, reads all caregivers, edits non-staff caregivers and
-- links them to patients; deleting a caregiver stays Admin only; a disabled doctor loses all of it.
-- Users: DA doctor (assigned to P1 only), CY caregiver account, AD admin account.
begin;
insert into auth.users (id, email) values
  ('a1970000-0000-0000-0000-000000000001', 'da@t'), ('a2970000-0000-0000-0000-000000000002', 'cy@t'), ('a3970000-0000-0000-0000-000000000003', 'ad@t');
update profiles set is_active = true where id::text like 'a_970000%';
insert into user_roles (user_id, role) values
  ('a1970000-0000-0000-0000-000000000001', 'doctor'), ('a2970000-0000-0000-0000-000000000002', 'caregiver'), ('a3970000-0000-0000-0000-000000000003', 'admin');
insert into patients (id, full_name) values ('b1970000-0000-0000-0000-000000000001', 'P1'), ('b2970000-0000-0000-0000-000000000002', 'P2');
insert into doctors (id, user_id, full_name) values ('d1970000-0000-0000-0000-000000000001', 'a1970000-0000-0000-0000-000000000001', 'DA');
insert into patient_doctors (patient_id, doctor_id) values ('b1970000-0000-0000-0000-000000000001', 'd1970000-0000-0000-0000-000000000001');
insert into caregivers (id, user_id, full_name) values ('c1970000-0000-0000-0000-000000000001', 'a2970000-0000-0000-0000-000000000002', 'CY');
insert into caregivers (id, user_id, full_name) values ('c2970000-0000-0000-0000-000000000002', null, 'unlinked');
insert into medicines (id, generic_name) values ('e1970000-0000-0000-0000-000000000001', 'M1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1970000-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  assert (select count(*) from patients where id::text like '_1970000%' or id::text like '_2970000%') = 2, 'doctor does not see every patient';
  assert (select count(*) from caregivers where id::text like 'c_970000%') = 2, 'doctor does not read every caregiver';
  assert save_plan(null, 'b2970000-0000-0000-0000-000000000002', 'e1970000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active') is not null, 'doctor cannot plan an unassigned patient';
  update caregivers set phone = '0812345678' where id = 'c1970000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor cannot edit a caregiver';
  insert into patient_caregivers (patient_id, caregiver_id, relationship) values ('b2970000-0000-0000-0000-000000000002', 'c1970000-0000-0000-0000-000000000001', 'son');
  update patient_caregivers set relationship = 'daughter' where caregiver_id = 'c1970000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor cannot edit a caregiver link';
  delete from patient_caregivers where caregiver_id = 'c1970000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor cannot unlink';
  delete from caregivers where id = 'c1970000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'doctor deleted a caregiver';
end $$;
reset role;

-- a disabled doctor sees nothing
update profiles set is_active = false where id = 'a1970000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1970000-0000-0000-0000-000000000001"}', true);
do $$
begin
  assert (select count(*) from patients where id::text like '_1970000%' or id::text like '_2970000%') = 0, 'disabled doctor sees patients';
  assert (select count(*) from caregivers where id::text like 'c_970000%') = 0, 'disabled doctor reads caregivers';
end $$;
reset role;
rollback;
