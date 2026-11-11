-- integration.sql section 12: who may change accounts. Users: A1 admin (caller), A2 another admin, DA doctor, DB another doctor,
-- CG caregiver, PU patient.
begin;

insert into auth.users (id, email) values
  ('a1900000-0000-0000-0000-000000000001', 'a1@t'), ('a2900000-0000-0000-0000-000000000002', 'a2@t'),
  ('a3900000-0000-0000-0000-000000000003', 'da@t'), ('a5900000-0000-0000-0000-000000000005', 'db@t'),
  ('a4900000-0000-0000-0000-000000000004', 'cg@t'), ('a6900000-0000-0000-0000-000000000006', 'pu@t');
update profiles set is_active = true where id::text like 'a_900000%';
insert into user_roles (user_id, role) values
  ('a1900000-0000-0000-0000-000000000001', 'admin'), ('a2900000-0000-0000-0000-000000000002', 'admin'),
  ('a3900000-0000-0000-0000-000000000003', 'doctor'), ('a5900000-0000-0000-0000-000000000005', 'doctor'),
  ('a4900000-0000-0000-0000-000000000004', 'caregiver'), ('a6900000-0000-0000-0000-000000000006', 'patient');

-- ===== admin: edits any account but never its own =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1900000-0000-0000-0000-000000000001"}', true);
do $$
begin
  begin insert into user_roles (user_id, role) values ('a1900000-0000-0000-0000-000000000001', 'caregiver'); raise exception 'admin granted itself a role';
  exception when insufficient_privilege then null; end;
  delete from user_roles where user_id = 'a1900000-0000-0000-0000-000000000001';
  update profiles set is_active = false where id = 'a1900000-0000-0000-0000-000000000001';
  begin perform delete_user('a1900000-0000-0000-0000-000000000001'); raise exception 'admin deleted itself';
  exception when invalid_parameter_value then null; end;
  -- another account, staff or not: role change, disable
  insert into user_roles (user_id, role) values ('a4900000-0000-0000-0000-000000000004', 'doctor');
  delete from user_roles where user_id = 'a4900000-0000-0000-0000-000000000004' and role <> 'doctor';
  update profiles set is_active = false where id = 'a2900000-0000-0000-0000-000000000002';
end $$;
reset role;
do $$
begin
  assert (select count(*) from user_roles where user_id = 'a1900000-0000-0000-0000-000000000001' and role = 'admin') = 1, 'admin lost its own role';
  assert (select is_active from profiles where id = 'a1900000-0000-0000-0000-000000000001'), 'admin disabled itself';
  assert (select role::text from user_roles where user_id = 'a4900000-0000-0000-0000-000000000004') = 'doctor', 'admin could not promote another account';
  assert not (select is_active from profiles where id = 'a2900000-0000-0000-0000-000000000002'), 'admin could not disable another admin';
end $$;
update user_roles set role = 'caregiver' where user_id = 'a4900000-0000-0000-0000-000000000004';
update profiles set is_active = true where id = 'a2900000-0000-0000-0000-000000000002';

-- ===== doctor DA: reads the list, edits only non-staff accounts (caregiver / patient), cannot delete accounts =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3900000-0000-0000-0000-000000000003"}', true);
do $$
begin
  assert (select count(*) from profiles where id::text like 'a_900000%') = 6, 'doctor cannot read the account list';
  assert (select count(*) from user_roles where user_id::text like 'a_900000%') = 6, 'doctor cannot read the roles';
  -- no granting admin / doctor, not even to a non-staff account, and nothing on itself
  begin insert into user_roles (user_id, role) values ('a4900000-0000-0000-0000-000000000004', 'admin'); raise exception 'doctor made an admin';
  exception when insufficient_privilege then null; end;
  begin insert into user_roles (user_id, role) values ('a6900000-0000-0000-0000-000000000006', 'doctor'); raise exception 'doctor made a doctor';
  exception when insufficient_privilege then null; end;
  begin insert into user_roles (user_id, role) values ('a3900000-0000-0000-0000-000000000003', 'patient'); raise exception 'doctor gave itself a role';
  exception when insufficient_privilege then null; end;
  -- staff accounts are untouchable
  delete from user_roles where user_id in ('a1900000-0000-0000-0000-000000000001', 'a5900000-0000-0000-0000-000000000005', 'a3900000-0000-0000-0000-000000000003');
  update profiles set is_active = false where id in ('a1900000-0000-0000-0000-000000000001', 'a5900000-0000-0000-0000-000000000005', 'a3900000-0000-0000-0000-000000000003');
  begin perform delete_user('a4900000-0000-0000-0000-000000000004'); raise exception 'doctor deleted an account';
  exception when insufficient_privilege then null; end;
  -- ordinary accounts: caregiver -> patient, disable
  insert into user_roles (user_id, role) values ('a4900000-0000-0000-0000-000000000004', 'patient');
  delete from user_roles where user_id = 'a4900000-0000-0000-0000-000000000004' and role <> 'patient';
  update profiles set is_active = false where id = 'a4900000-0000-0000-0000-000000000004';
  -- the caregivers row for an account made a caregiver; not for a staff account
  insert into caregivers (user_id, full_name) values ('a6900000-0000-0000-0000-000000000006', 'PU as caregiver');
  begin insert into caregivers (user_id, full_name) values ('a5900000-0000-0000-0000-000000000005', 'staff'); raise exception 'doctor made a caregiver row for staff';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$
begin
  assert (select count(*) from user_roles where user_id in ('a1900000-0000-0000-0000-000000000001', 'a5900000-0000-0000-0000-000000000005', 'a3900000-0000-0000-0000-000000000003')) = 3, 'doctor removed a staff role';
  assert (select count(*) from profiles where is_active and id::text like 'a_900000%') = 5, 'doctor disabled a staff profile or failed to disable the caregiver';
  assert (select role::text from user_roles where user_id = 'a4900000-0000-0000-0000-000000000004') = 'patient', 'doctor could not change a normal account';
end $$;

-- a disabled doctor loses the powers
update profiles set is_active = false where id = 'a5900000-0000-0000-0000-000000000005';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5900000-0000-0000-0000-000000000005"}', true);
do $$
begin
  assert (select count(*) from profiles where id::text like 'a_900000%') = 1, 'disabled doctor reads the account list';
  update profiles set is_active = true where id = 'a4900000-0000-0000-0000-000000000004';
end $$;
reset role;
do $$ begin assert not (select is_active from profiles where id = 'a4900000-0000-0000-0000-000000000004'), 'disabled doctor changed an account'; end $$;

-- ===== admin deletes an account (staff too) =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1900000-0000-0000-0000-000000000001"}', true);
select delete_user('a6900000-0000-0000-0000-000000000006');
reset role;
do $$ begin assert not exists (select 1 from auth.users where id = 'a6900000-0000-0000-0000-000000000006'), 'admin could not delete an account'; end $$;

rollback;
