-- integration.sql section 16: a doctor edits caregivers rows (cg_u_doctor) but may not re-point user_id, i.e. hand a relative's
-- confirmed patient links to another account. Admin still can.
-- Users: DA doctor, CY caregiver (linked to P1), XX another non-staff account, AD admin.
begin;
insert into auth.users (id, email) values
  ('a1980000-0000-0000-0000-000000000001', 'da@t'), ('a2980000-0000-0000-0000-000000000002', 'cy@t'),
  ('a3980000-0000-0000-0000-000000000003', 'xx@t'), ('a4980000-0000-0000-0000-000000000004', 'ad@t');
update profiles set is_active = true where id::text like 'a_980000%';
insert into user_roles (user_id, role) values
  ('a1980000-0000-0000-0000-000000000001', 'doctor'), ('a2980000-0000-0000-0000-000000000002', 'caregiver'),
  ('a3980000-0000-0000-0000-000000000003', 'caregiver'), ('a4980000-0000-0000-0000-000000000004', 'admin');
insert into patients (id, full_name) values ('b1980000-0000-0000-0000-000000000001', 'P1');
insert into caregivers (id, user_id, full_name) values
  ('c1980000-0000-0000-0000-000000000001', 'a2980000-0000-0000-0000-000000000002', 'CY'),
  ('c2980000-0000-0000-0000-000000000002', null, 'no account');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('b1980000-0000-0000-0000-000000000001', 'c1980000-0000-0000-0000-000000000001', 'confirmed', true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1980000-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  -- positive control: contact details stay editable
  update caregivers set phone = '0811111111' where id = 'c1980000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'doctor could not edit caregiver phone';
  begin
    update caregivers set user_id = 'a3980000-0000-0000-0000-000000000003' where id = 'c1980000-0000-0000-0000-000000000001';
    raise exception 'doctor re-pointed a linked caregiver to another account';
  exception when insufficient_privilege then null;
  end;
  begin
    update caregivers set user_id = 'a3980000-0000-0000-0000-000000000003' where id = 'c2980000-0000-0000-0000-000000000002';
    raise exception 'doctor attached an account to a caregiver row';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select user_id from caregivers where id = 'c1980000-0000-0000-0000-000000000001') = 'a2980000-0000-0000-0000-000000000002', 'owner changed';
end $$;

-- the relative still reads the patient; admin may still re-point
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2980000-0000-0000-0000-000000000002"}', true);
do $$ begin assert (select count(*) from patients where id = 'b1980000-0000-0000-0000-000000000001') = 1, 'relative lost access'; end $$;
select set_config('request.jwt.claims', '{"sub":"a4980000-0000-0000-0000-000000000004"}', true);
update caregivers set user_id = 'a3980000-0000-0000-0000-000000000003' where id = 'c2980000-0000-0000-0000-000000000002';
reset role;
do $$
begin
  assert (select user_id from caregivers where id = 'c2980000-0000-0000-0000-000000000002') = 'a3980000-0000-0000-0000-000000000003', 'admin could not re-point';
end $$;
rollback;
