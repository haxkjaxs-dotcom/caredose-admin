-- integration.sql section 20: the name sync (security definer) must not let a doctor rename a STAFF account through a row the doctor
-- may edit (any patients row, patients_u_doctor), since profiles_u forbids that directly. Admin and non-staff renames still sync.
-- Users: DA doctor, DB doctor who was a patient before (still has a patients row), PU patient, AD admin.
begin;
insert into auth.users (id, email) values
  ('a1101000-0000-0000-0000-000000000001', 'da@t'), ('a1102000-0000-0000-0000-000000000002', 'db@t'),
  ('a1103000-0000-0000-0000-000000000003', 'pu@t'), ('a1104000-0000-0000-0000-000000000004', 'ad@t');
update profiles set is_active = true where id::text like 'a110_000%';
update profiles set full_name = 'DB' where id = 'a1102000-0000-0000-0000-000000000002';
update profiles set full_name = 'PU' where id = 'a1103000-0000-0000-0000-000000000003';
insert into user_roles (user_id, role) values
  ('a1101000-0000-0000-0000-000000000001', 'doctor'), ('a1102000-0000-0000-0000-000000000002', 'doctor'),
  ('a1103000-0000-0000-0000-000000000003', 'patient'), ('a1104000-0000-0000-0000-000000000004', 'admin');
insert into doctors (id, user_id, full_name) values ('d1102000-0000-0000-0000-000000000002', 'a1102000-0000-0000-0000-000000000002', 'DB');
insert into patients (id, user_id, full_name) values
  ('b1102000-0000-0000-0000-000000000002', 'a1102000-0000-0000-0000-000000000002', 'DB'),
  ('b1103000-0000-0000-0000-000000000003', 'a1103000-0000-0000-0000-000000000003', 'PU');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1101000-0000-0000-0000-000000000001"}', true);
update patients set full_name = 'Fake' where id = 'b1102000-0000-0000-0000-000000000002';
update patients set full_name = 'PU2' where id = 'b1103000-0000-0000-0000-000000000003';
reset role;
do $$
begin
  assert (select full_name from profiles where id = 'a1102000-0000-0000-0000-000000000002') = 'DB', 'doctor renamed a staff profile via patients';
  assert (select full_name from doctors where id = 'd1102000-0000-0000-0000-000000000002') = 'DB', 'doctor renamed a staff doctors row via patients';
  assert (select full_name from profiles where id = 'a1103000-0000-0000-0000-000000000003') = 'PU2', 'non-staff rename by a doctor did not sync';
end $$;

-- admin may rename the staff account and it syncs
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1104000-0000-0000-0000-000000000004"}', true);
update patients set full_name = 'DB2' where id = 'b1102000-0000-0000-0000-000000000002';
reset role;
do $$
begin
  assert (select full_name from profiles where id = 'a1102000-0000-0000-0000-000000000002') = 'DB2', 'admin rename did not sync';
  assert (select full_name from doctors where id = 'd1102000-0000-0000-0000-000000000002') = 'DB2', 'admin rename did not reach doctors';
end $$;
rollback;
