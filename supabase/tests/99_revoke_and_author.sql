-- integration.sql section 17:
--  * a link the patient revoked stays revoked: a doctor (pc_u_doctor / pc_d_doctor) can neither re-confirm it nor delete it to
--    insert a fresh one. Admin still can.
--  * follow_ups.by_name is the author's profile name, never free text from the client.
-- Users: DA doctor, CY caregiver (link revoked by the patient), CM caregiver (link confirmed, can_manage_plan), PU patient, AD admin.
begin;
insert into auth.users (id, email) values
  ('a1990000-0000-0000-0000-000000000001', 'da@t'), ('a2990000-0000-0000-0000-000000000002', 'cy@t'),
  ('a3990000-0000-0000-0000-000000000003', 'cm@t'), ('a4990000-0000-0000-0000-000000000004', 'pu@t'),
  ('a5990000-0000-0000-0000-000000000005', 'ad@t');
update profiles set is_active = true where id::text like 'a_990000%';
update profiles set full_name = 'ญาติ CM' where id = 'a3990000-0000-0000-0000-000000000003';
update profiles set full_name = 'หมอ DA' where id = 'a1990000-0000-0000-0000-000000000001';
insert into user_roles (user_id, role) values
  ('a1990000-0000-0000-0000-000000000001', 'doctor'), ('a2990000-0000-0000-0000-000000000002', 'caregiver'),
  ('a3990000-0000-0000-0000-000000000003', 'caregiver'), ('a4990000-0000-0000-0000-000000000004', 'patient'),
  ('a5990000-0000-0000-0000-000000000005', 'admin');
insert into patients (id, user_id, full_name) values ('b1990000-0000-0000-0000-000000000001', 'a4990000-0000-0000-0000-000000000004', 'P1');
insert into caregivers (id, user_id, full_name) values
  ('c1990000-0000-0000-0000-000000000001', 'a2990000-0000-0000-0000-000000000002', 'CY'),
  ('c2990000-0000-0000-0000-000000000002', 'a3990000-0000-0000-0000-000000000003', 'CM');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('b1990000-0000-0000-0000-000000000001', 'c1990000-0000-0000-0000-000000000001', 'confirmed', false),
  ('b1990000-0000-0000-0000-000000000001', 'c2990000-0000-0000-0000-000000000002', 'confirmed', true);

-- the patient revokes CY
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a4990000-0000-0000-0000-000000000004"}', true);
update patient_caregivers set status = 'revoked', revoked_at = now() where caregiver_id = 'c1990000-0000-0000-0000-000000000001';
-- ===== 1) the doctor cannot undo it =====
select set_config('request.jwt.claims', '{"sub":"a1990000-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  update patient_caregivers set status = 'confirmed', revoked_at = null where caregiver_id = 'c1990000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'doctor re-confirmed a link the patient revoked';
  delete from patient_caregivers where caregiver_id = 'c1990000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'doctor deleted a revoked link (and could re-insert it confirmed)';
  -- the doctor cannot create a link already marked revoked-then-confirmed either: the row still exists, so insert conflicts
  begin
    insert into patient_caregivers (patient_id, caregiver_id, status) values
      ('b1990000-0000-0000-0000-000000000001', 'c1990000-0000-0000-0000-000000000001', 'confirmed');
    raise exception 'doctor inserted a second link';
  exception when unique_violation then null;
  end;
  -- positive control: a live link is still editable / removable by the doctor
  update patient_caregivers set relationship = 'son' where caregiver_id = 'c2990000-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  assert n = 1, 'doctor could not edit a live link';
  -- and the doctor cannot revoke-and-then-flip a live link back in one go: revoking is fine, re-confirming is not
  update patient_caregivers set status = 'revoked' where caregiver_id = 'c2990000-0000-0000-0000-000000000002';
  update patient_caregivers set status = 'confirmed' where caregiver_id = 'c2990000-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'doctor re-confirmed a revoked link';
end $$;
reset role;
do $$
begin
  assert (select status from patient_caregivers where caregiver_id = 'c1990000-0000-0000-0000-000000000001') = 'revoked', 'revocation undone';
end $$;
-- admin may still restore it
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5990000-0000-0000-0000-000000000005"}', true);
update patient_caregivers set status = 'confirmed', revoked_at = null where caregiver_id = 'c2990000-0000-0000-0000-000000000002';
reset role;
do $$
begin
  assert (select status from patient_caregivers where caregiver_id = 'c2990000-0000-0000-0000-000000000002') = 'confirmed', 'admin could not restore';
end $$;

-- ===== 2) follow-up author name comes from the profile =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3990000-0000-0000-0000-000000000003"}', true);
insert into follow_ups (patient_id, note, by_name, created_by) values
  ('b1990000-0000-0000-0000-000000000001', 'n1', 'หมอ DA', 'a3990000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', '{"sub":"a1990000-0000-0000-0000-000000000001"}', true);
insert into follow_ups (patient_id, note, by_name, created_by) values
  ('b1990000-0000-0000-0000-000000000001', 'n2', 'x', 'a1990000-0000-0000-0000-000000000001');
reset role;
do $$
begin
  assert (select by_name from follow_ups where note = 'n1') = 'ญาติ CM', 'caregiver signed a note as someone else';
  assert (select by_name from follow_ups where note = 'n2') = 'หมอ DA', 'doctor note not stamped';
end $$;
rollback;
