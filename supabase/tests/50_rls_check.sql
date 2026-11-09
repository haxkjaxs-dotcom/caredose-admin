-- RLS CHECK for the patient-data tables. Self-contained: paste the whole file into the Supabase SQL Editor and Run.
-- It needs schema.sql, security_fixes.sql and integration.sql (save_plan) applied first.
-- Everything runs inside begin ... rollback, so no fixture row survives. Any violated expectation raises an
-- exception (the run turns red); success ends with the notice "RLS CHECK PASSED".
-- It creates its own users in auth.users with only the columns that exist on a real project and in the local PGlite stub
-- (id, email). On a real project the SQL editor's role can insert into auth.users; the on_auth_user_created trigger
-- then creates the (disabled) profiles. Fixture emails end in @rls-check.invalid, so they cannot collide with real accounts.
-- Fixtures: A, B patients; CG caregiver of A with can_manage_plan = false; DIS disabled account (admin + patient) with its own data.
begin;

create function _rls_check(ok boolean, msg text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'RLS CHECK FAILED: %', msg; end if;
end $$;

insert into auth.users (id, email) values
  ('aa100000-0000-0000-0000-000000000001', 'a@rls-check.invalid'),
  ('bb200000-0000-0000-0000-000000000002', 'b@rls-check.invalid'),
  ('cc300000-0000-0000-0000-000000000003', 'cg@rls-check.invalid'),
  ('dd400000-0000-0000-0000-000000000004', 'dis@rls-check.invalid');
-- profiles start disabled (security_fixes #2); DIS stays that way
update profiles set is_active = true
  where id in ('aa100000-0000-0000-0000-000000000001', 'bb200000-0000-0000-0000-000000000002', 'cc300000-0000-0000-0000-000000000003');
update profiles set is_active = false where id = 'dd400000-0000-0000-0000-000000000004';
insert into user_roles (user_id, role) values
  ('aa100000-0000-0000-0000-000000000001', 'patient'),
  ('bb200000-0000-0000-0000-000000000002', 'patient'),
  ('cc300000-0000-0000-0000-000000000003', 'caregiver'),
  ('dd400000-0000-0000-0000-000000000004', 'admin'),
  ('dd400000-0000-0000-0000-000000000004', 'patient');
insert into patients (id, user_id, full_name) values
  ('a1000000-0000-0000-0000-0000000000a1', 'aa100000-0000-0000-0000-000000000001', 'RLS Patient A'),
  ('b2000000-0000-0000-0000-0000000000b2', 'bb200000-0000-0000-0000-000000000002', 'RLS Patient B'),
  ('d4000000-0000-0000-0000-0000000000d4', 'dd400000-0000-0000-0000-000000000004', 'RLS Disabled');
insert into caregivers (id, user_id, full_name) values
  ('c3000000-0000-0000-0000-0000000000c3', 'cc300000-0000-0000-0000-000000000003', 'RLS Caregiver');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('a1000000-0000-0000-0000-0000000000a1', 'c3000000-0000-0000-0000-0000000000c3', 'confirmed', false),
  ('d4000000-0000-0000-0000-0000000000d4', 'c3000000-0000-0000-0000-0000000000c3', 'confirmed', true);
insert into medicines (id, generic_name) values ('e0000000-0000-0000-0000-0000000000e0', 'RLS check medicine');

-- one plan + schedule per patient; logs: A has a recent one and one 25 h old, B has one, DIS has one
insert into medication_plans (id, patient_id, medicine_id, dose, start_date) values
  ('a1100000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'A dose', current_date),
  ('b2200000-0000-0000-0000-0000000000b2', 'b2000000-0000-0000-0000-0000000000b2', 'e0000000-0000-0000-0000-0000000000e0', 'B dose', current_date),
  ('d4400000-0000-0000-0000-0000000000d4', 'd4000000-0000-0000-0000-0000000000d4', 'e0000000-0000-0000-0000-0000000000e0', 'D dose', current_date);
insert into medication_schedules (id, plan_id, time_of_day) values
  ('a1110000-0000-0000-0000-0000000000a1', 'a1100000-0000-0000-0000-0000000000a1', '08:00'),
  ('b2220000-0000-0000-0000-0000000000b2', 'b2200000-0000-0000-0000-0000000000b2', '08:00'),
  ('d4440000-0000-0000-0000-0000000000d4', 'd4400000-0000-0000-0000-0000000000d4', '08:00');
insert into medication_logs (id, plan_id, schedule_id, scheduled_at, recorded_by, note) values
  ('a1111000-0000-0000-0000-0000000000a1', 'a1100000-0000-0000-0000-0000000000a1', 'a1110000-0000-0000-0000-0000000000a1', now() - interval '1 hour', 'aa100000-0000-0000-0000-000000000001', 'recent'),
  ('a1112000-0000-0000-0000-0000000000a2', 'a1100000-0000-0000-0000-0000000000a1', 'a1110000-0000-0000-0000-0000000000a1', now() - interval '25 hours', 'aa100000-0000-0000-0000-000000000001', 'old'),
  ('b2221000-0000-0000-0000-0000000000b2', 'b2200000-0000-0000-0000-0000000000b2', 'b2220000-0000-0000-0000-0000000000b2', now() - interval '1 hour', 'bb200000-0000-0000-0000-000000000002', 'B log'),
  ('d4441000-0000-0000-0000-0000000000d4', 'd4400000-0000-0000-0000-0000000000d4', 'd4440000-0000-0000-0000-0000000000d4', now() - interval '1 hour', 'dd400000-0000-0000-0000-000000000004', 'D log');
insert into appointments (patient_id, appointment_at) values
  ('a1000000-0000-0000-0000-0000000000a1', now()), ('b2000000-0000-0000-0000-0000000000b2', now()), ('d4000000-0000-0000-0000-0000000000d4', now());
insert into bmi_logs (patient_id, weight_kg, height_cm, bmi_value, category) values
  ('b2000000-0000-0000-0000-0000000000b2', 60, 170, 20.8, 'normal'), ('d4000000-0000-0000-0000-0000000000d4', 60, 170, 20.8, 'normal');
insert into follow_ups (patient_id, note, by_name) values
  ('b2000000-0000-0000-0000-0000000000b2', 'n', 'x'), ('d4000000-0000-0000-0000-0000000000d4', 'n', 'x');
insert into notifications (user_id, type, title) values ('dd400000-0000-0000-0000-000000000004', 't', 'for the disabled account');

-- ===== patient A: reads only own data =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-0000-0000-000000000001"}', true);
do $$
begin
  perform _rls_check((select count(*) from patients) = 1 and exists (select 1 from patients where id = 'a1000000-0000-0000-0000-0000000000a1'), 'A should see only own patient row');
  perform _rls_check(not exists (select 1 from patients where id = 'b2000000-0000-0000-0000-0000000000b2'), 'A sees patient B');
  perform _rls_check((select count(*) from medication_plans) = 1 and exists (select 1 from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1'), 'A should see only own plan');
  perform _rls_check(not exists (select 1 from medication_plans where id = 'b2200000-0000-0000-0000-0000000000b2'), 'A sees B plan');
  perform _rls_check((select count(*) from medication_schedules) = 1, 'A should see only own schedule');
  perform _rls_check((select count(*) from medication_logs) = 2, 'A should see only own 2 logs');
  perform _rls_check(not exists (select 1 from medication_logs where id = 'b2221000-0000-0000-0000-0000000000b2'), 'A sees B log');
  perform _rls_check(not exists (select 1 from appointments where patient_id = 'b2000000-0000-0000-0000-0000000000b2'), 'A sees B appointment');
  perform _rls_check(not exists (select 1 from bmi_logs where patient_id = 'b2000000-0000-0000-0000-0000000000b2'), 'A sees B bmi');
  perform _rls_check(not exists (select 1 from follow_ups where patient_id = 'b2000000-0000-0000-0000-0000000000b2'), 'A sees B follow-ups');
end $$;

-- ===== patient A: log inserts =====
do $$
declare n int;
begin
  -- own plan, recorded_by = own uid: allowed
  insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
    values ('a1100000-0000-0000-0000-0000000000a1', 'a1110000-0000-0000-0000-0000000000a1', now() + interval '2 hours', 'aa100000-0000-0000-0000-000000000001');
  -- someone else's plan
  begin
    insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
      values ('b2200000-0000-0000-0000-0000000000b2', 'b2220000-0000-0000-0000-0000000000b2', now() + interval '2 hours', 'aa100000-0000-0000-0000-000000000001');
    raise exception 'RLS CHECK FAILED: A inserted a log on B plan';
  exception when insufficient_privilege then null;
  end;
  -- own plan but recorded_by someone else, or empty
  begin
    insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
      values ('a1100000-0000-0000-0000-0000000000a1', 'a1110000-0000-0000-0000-0000000000a1', now() + interval '3 hours', 'bb200000-0000-0000-0000-000000000002');
    raise exception 'RLS CHECK FAILED: A inserted a log with recorded_by = B';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into medication_logs (plan_id, schedule_id, scheduled_at)
      values ('a1100000-0000-0000-0000-0000000000a1', 'a1110000-0000-0000-0000-0000000000a1', now() + interval '4 hours');
    raise exception 'RLS CHECK FAILED: A inserted a log with no recorded_by';
  exception when insufficient_privilege then null;
  end;

  -- updates: within 24 h ok (positive control), older than 24 h or someone else's log: 0 rows
  update medication_logs set note = 'edited' where id = 'a1111000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 1, 'A could not edit a recent own log (rows=' || n || ')');
  update medication_logs set note = 'edited' where id = 'a1112000-0000-0000-0000-0000000000a2';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'A edited a log older than 24 h (rows=' || n || ')');
  update medication_logs set note = 'edited' where id = 'b2221000-0000-0000-0000-0000000000b2';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'A edited a log of B (rows=' || n || ')');
  begin
    update medication_logs set recorded_by = 'bb200000-0000-0000-0000-000000000002' where id = 'a1111000-0000-0000-0000-0000000000a1';
    raise exception 'RLS CHECK FAILED: A re-pointed recorded_by to B';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ===== patient A cannot change own plan (direct writes and save_plan) =====
do $$
declare n int;
begin
  update medication_plans set dose = 'hacked' where id = 'a1100000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'A updated own plan (rows=' || n || ')');
  delete from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'A deleted own plan (rows=' || n || ')');
  delete from medication_schedules where id = 'a1110000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'A deleted own schedule (rows=' || n || ')');
  begin
    insert into medication_plans (patient_id, medicine_id, dose, start_date)
      values ('a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'x', current_date);
    raise exception 'RLS CHECK FAILED: A inserted a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into medication_schedules (plan_id, time_of_day) values ('a1100000-0000-0000-0000-0000000000a1', '12:00');
    raise exception 'RLS CHECK FAILED: A inserted a schedule';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan('a1100000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'hacked', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: A edited own plan through save_plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan(null, 'a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'x', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: A created a plan through save_plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan(null, 'b2000000-0000-0000-0000-0000000000b2', 'e0000000-0000-0000-0000-0000000000e0', 'x', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: A created a plan for B through save_plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ===== patient B: cannot read or change A's data =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bb200000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  perform _rls_check((select count(*) from patients) = 1 and not exists (select 1 from patients where id = 'a1000000-0000-0000-0000-0000000000a1'), 'B sees patient A');
  perform _rls_check(not exists (select 1 from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1'), 'B sees A plan');
  perform _rls_check(not exists (select 1 from medication_logs where plan_id = 'a1100000-0000-0000-0000-0000000000a1'), 'B sees A logs');
  update medication_logs set note = 'edited' where id = 'a1111000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'B edited A log (rows=' || n || ')');
end $$;
reset role;

-- ===== caregiver without can_manage_plan: reads A (control), changes nothing =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"cc300000-0000-0000-0000-000000000003"}', true);
do $$
declare n int;
begin
  perform _rls_check(exists (select 1 from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1'), 'caregiver cannot read A plan (control)');
  begin
    insert into medication_plans (patient_id, medicine_id, dose, start_date)
      values ('a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'x', current_date);
    raise exception 'RLS CHECK FAILED: caregiver without can_manage_plan inserted a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into medication_schedules (plan_id, time_of_day) values ('a1100000-0000-0000-0000-0000000000a1', '12:00');
    raise exception 'RLS CHECK FAILED: caregiver without can_manage_plan inserted a schedule';
  exception when insufficient_privilege then null;
  end;
  update medication_plans set dose = 'hacked' where id = 'a1100000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'caregiver updated a plan (rows=' || n || ')');
  delete from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  perform _rls_check(n = 0, 'caregiver deleted a plan (rows=' || n || ')');
  begin
    perform save_plan(null, 'a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'x', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: caregiver without can_manage_plan created a plan through save_plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan('a1100000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000e0', 'hacked', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: caregiver without can_manage_plan edited a plan through save_plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ===== disabled account: 0 rows in every patient-data table, and no save_plan =====
-- (doctors/medicines are readable by any signed-in user by design and are not asserted)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"dd400000-0000-0000-0000-000000000004"}', true);
do $$
declare t text; n int;
begin
  foreach t in array array['patients', 'medication_plans', 'medication_schedules', 'medication_logs', 'appointments', 'bmi_logs',
                           'follow_ups', 'patient_doctors', 'patient_caregivers', 'notifications'] loop
    execute format('select count(*) from %I', t) into n;
    perform _rls_check(n = 0, 'disabled account sees ' || n || ' rows in ' || t);
  end loop;
  begin
    perform save_plan('d4400000-0000-0000-0000-0000000000d4', 'd4000000-0000-0000-0000-0000000000d4', 'e0000000-0000-0000-0000-0000000000e0', 'x', null, current_date, null, null, array['08:00'], 'active');
    raise exception 'RLS CHECK FAILED: disabled account used save_plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ===== nothing the refused attempts touched has changed =====
do $$
begin
  perform _rls_check((select dose from medication_plans where id = 'a1100000-0000-0000-0000-0000000000a1') = 'A dose', 'A plan changed');
  perform _rls_check((select count(*) from medication_plans where patient_id = 'a1000000-0000-0000-0000-0000000000a1') = 1, 'A plan count changed');
  perform _rls_check((select count(*) from medication_schedules where plan_id = 'a1100000-0000-0000-0000-0000000000a1') = 1, 'A schedule count changed');
  perform _rls_check((select note from medication_logs where id = 'a1112000-0000-0000-0000-0000000000a2') = 'old', 'old A log changed');
  perform _rls_check((select note from medication_logs where id = 'b2221000-0000-0000-0000-0000000000b2') = 'B log', 'B log changed');
  perform _rls_check((select count(*) from medication_plans where patient_id = 'b2000000-0000-0000-0000-0000000000b2') = 1, 'B plans changed');
  -- A's one allowed insert + one allowed edit are the only log changes
  perform _rls_check((select count(*) from medication_logs where plan_id = 'a1100000-0000-0000-0000-0000000000a1') = 3, 'A log count');
end $$;

do $$ begin raise notice 'RLS CHECK PASSED'; end $$;
rollback;
