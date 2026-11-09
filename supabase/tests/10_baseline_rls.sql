-- Baseline RLS checks on the unmodified schema.sql + security_fixes.sql.
-- A = patient, B = other patient, C = disabled account (also admin role + own patient row),
-- D = caregiver of A (can_manage_plan = false).
begin;

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@t'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@t'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@t'),
  ('dddddddd-0000-0000-0000-000000000004', 'd@t');
-- on_auth_user_created made the profiles; they start disabled (security_fixes #2)
update profiles set is_active = true where id <> 'cccccccc-0000-0000-0000-000000000003';
update profiles set is_active = false where id = 'cccccccc-0000-0000-0000-000000000003';

insert into user_roles (user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'patient'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'patient'),
  ('cccccccc-0000-0000-0000-000000000003', 'admin'),
  ('dddddddd-0000-0000-0000-000000000004', 'caregiver');

insert into patients (id, user_id, full_name) values
  ('a1111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Patient A'),
  ('b2222222-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000002', 'Patient B'),
  ('c3333333-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003', 'Patient C');
insert into caregivers (id, user_id, full_name) values
  ('d4444444-0000-0000-0000-000000000004', 'dddddddd-0000-0000-0000-000000000004', 'Caregiver D');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('a1111111-0000-0000-0000-000000000001', 'd4444444-0000-0000-0000-000000000004', 'confirmed', false);
insert into doctors (id, full_name) values ('e5555555-0000-0000-0000-000000000005', 'Doctor E');
insert into patient_doctors (patient_id, doctor_id) values
  ('a1111111-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000005'),
  ('c3333333-0000-0000-0000-000000000003', 'e5555555-0000-0000-0000-000000000005');
insert into medicines (id, generic_name) values ('f6666666-0000-0000-0000-000000000006', 'Paracetamol');

-- one plan + schedule + log + appointment + bmi + follow-up per patient
do $$
declare r record; plan uuid; sched uuid;
begin
  for r in select id, user_id from patients loop
    insert into medication_plans (patient_id, medicine_id, dose, start_date)
      values (r.id, 'f6666666-0000-0000-0000-000000000006', '1 tab', current_date) returning id into plan;
    insert into medication_schedules (plan_id, time_of_day) values (plan, '08:00') returning id into sched;
    insert into medication_logs (plan_id, schedule_id, scheduled_at) values (plan, sched, now());
    insert into appointments (patient_id, appointment_at) values (r.id, now());
    insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values (r.id, 60, 170, 20.8, 'normal');
    insert into follow_ups (patient_id, note, by_name) values (r.id, 'n', 'x');
  end loop;
end $$;

-- ===== check 1: patient A sees only own patient row; B's data is invisible =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  select count(*) into n from patients;
  assert n = 1, 'check1: A should see exactly 1 patient row, saw ' || n;
  assert (select user_id from patients) = 'aaaaaaaa-0000-0000-0000-000000000001', 'check1: A sees a row that is not A';
  select count(*) into n from medication_plans;
  assert n = 1, 'check1b: A should see own plan only, saw ' || n; -- positive control
end $$;

-- ===== check 2: A sees 0 of B's plan/schedule/log/appointment/bmi/follow-up =====
do $$
declare bp constant uuid := 'b2222222-0000-0000-0000-000000000002'; n int;
begin
  select count(*) into n from medication_plans where patient_id = bp;
  assert n = 0, 'check2: A sees B plans: ' || n;
  select count(*) into n from medication_schedules s join medication_plans p on p.id = s.plan_id where p.patient_id = bp;
  assert n = 0, 'check2: A sees B schedules: ' || n;
  select count(*) into n from medication_logs l join medication_plans p on p.id = l.plan_id where p.patient_id = bp;
  assert n = 0, 'check2: A sees B logs: ' || n;
  select count(*) into n from appointments where patient_id = bp;
  assert n = 0, 'check2: A sees B appointments: ' || n;
  select count(*) into n from bmi_logs where patient_id = bp;
  assert n = 0, 'check2: A sees B bmi_logs: ' || n;
  select count(*) into n from follow_ups where patient_id = bp;
  assert n = 0, 'check2: A sees B follow_ups: ' || n;
end $$;

-- ===== check 3: disabled account C (admin role, own patient row) sees nothing in patient-data tables =====
-- doctors/medicines are readable by anyone (using (true)): existing behaviour, not asserted.
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-000000000003"}', true);
do $$
declare t text; n int;
begin
  foreach t in array array['patients','medication_plans','medication_schedules','medication_logs',
                           'appointments','bmi_logs','follow_ups','patient_doctors','patient_caregivers'] loop
    execute format('select count(*) from %I', t) into n;
    assert n = 0, 'check3: disabled account sees ' || n || ' rows in ' || t;
  end loop;
end $$;

-- ===== check 4: A re-pointing patients.user_id at B is blocked (RLS: 0 rows, row unchanged) =====
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  update patients set user_id = 'bbbbbbbb-0000-0000-0000-000000000002' where id = 'a1111111-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'check4: A updated ' || n || ' rows of patients.user_id';
  update patients set user_id = 'bbbbbbbb-0000-0000-0000-000000000002' where id = 'b2222222-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'check4: A updated B''s patient row';
end $$;
reset role;
do $$
begin
  assert (select user_id from patients where id = 'a1111111-0000-0000-0000-000000000001') = 'aaaaaaaa-0000-0000-0000-000000000001',
    'check4: patients.user_id of A changed';
  assert (select user_id from patients where id = 'b2222222-0000-0000-0000-000000000002') = 'bbbbbbbb-0000-0000-0000-000000000002',
    'check4: patients.user_id of B changed';
end $$;

-- ===== check 5: caregiver D with can_manage_plan = false cannot add a plan for A =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-000000000004"}', true);
do $$
begin
  begin
    insert into medication_plans (patient_id, medicine_id, dose, start_date)
      values ('a1111111-0000-0000-0000-000000000001', 'f6666666-0000-0000-0000-000000000006', 'x', current_date);
    raise exception 'check5: caregiver without can_manage_plan inserted a plan';
  exception when insufficient_privilege then
    null; -- 42501 expected
  end;
end $$;
-- positive control: same caregiver with can_manage_plan = true may insert
reset role;
update patient_caregivers set can_manage_plan = true;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-000000000004"}', true);
insert into medication_plans (patient_id, medicine_id, dose, start_date)
  values ('a1111111-0000-0000-0000-000000000001', 'f6666666-0000-0000-0000-000000000006', 'x', current_date);

rollback;
