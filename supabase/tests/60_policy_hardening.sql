-- Final-review fixes (integration.sql sections 8-9):
--  * doctors / medicines are readable only by an active account (a fresh phone sign-up is disabled and must see nothing)
--  * plans/schedules: doctors and managing caregivers may still insert and edit plans, but only admin deletes plans/schedules
--    or edits/deletes schedules (history stays), and a log must reference a schedule of its own plan.
-- Users: AD admin, DA doctor of P1, CY caregiver of P1 (can_manage_plan), CN caregiver of P1 (no manage), PU patient P1,
-- NEW a fresh sign-up (disabled, no role). Plan1 (08:00 schedule S1) and plan1b (09:00 schedule S1b) belong to P1, plan2 (S2) to P2.
begin;

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'ad@t'), ('a2000000-0000-0000-0000-000000000002', 'da@t'),
  ('a3000000-0000-0000-0000-000000000003', 'cy@t'), ('a4000000-0000-0000-0000-000000000004', 'cn@t'),
  ('a5000000-0000-0000-0000-000000000005', 'pu@t'), ('a6000000-0000-0000-0000-000000000006', 'new@t');
update profiles set is_active = true where id <> 'a6000000-0000-0000-0000-000000000006';
insert into user_roles (user_id, role) values
  ('a1000000-0000-0000-0000-000000000001', 'admin'), ('a2000000-0000-0000-0000-000000000002', 'doctor'),
  ('a3000000-0000-0000-0000-000000000003', 'caregiver'), ('a4000000-0000-0000-0000-000000000004', 'caregiver'),
  ('a5000000-0000-0000-0000-000000000005', 'patient');
insert into patients (id, user_id, full_name) values
  ('b1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005', 'P1'),
  ('b2000000-0000-0000-0000-000000000002', null, 'P2');
insert into doctors (id, user_id, full_name, phone) values ('d1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'DA', '0800000000');
insert into patient_doctors (patient_id, doctor_id) values ('b1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001');
insert into caregivers (id, user_id, full_name) values
  ('c1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'CY'),
  ('c2000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000004', 'CN');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('b1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'confirmed', true),
  ('b1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'confirmed', false);
insert into medicines (id, generic_name) values ('e1000000-0000-0000-0000-000000000001', 'M1');
insert into medication_plans (id, patient_id, medicine_id, dose, start_date) values
  ('f1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'D1', current_date),
  ('f1100000-0000-0000-0000-000000000011', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'D1b', current_date),
  ('f2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'D2', current_date);
insert into medication_schedules (id, plan_id, time_of_day) values
  ('51000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '08:00'),
  ('51100000-0000-0000-0000-000000000011', 'f1100000-0000-0000-0000-000000000011', '09:00'),
  ('52000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', '08:00');
insert into medication_logs (plan_id, schedule_id, scheduled_at) values
  ('f1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', now() - interval '1 hour');

-- ===== 1) doctors / medicines: a disabled account sees nothing, active accounts still see them =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a6000000-0000-0000-0000-000000000006"}', true);
do $$
begin
  assert (select count(*) from doctors) = 0, 'new account reads doctors';
  assert (select count(*) from medicines) = 0, 'new account reads medicines';
end $$;
reset role;
do $$
declare u text;
begin
  for u in select unnest(array['a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002',
                               'a3000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000005']) loop
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"' || u || '"}', true);
    assert (select count(*) from doctors) = 1, 'active ' || u || ' cannot read doctors';
    assert (select count(*) from medicines) = 1, 'active ' || u || ' cannot read medicines';
    reset role;
  end loop;
end $$;
-- an admin-disabled doctor loses it too
update profiles set is_active = false where id = 'a2000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  assert (select count(*) from doctors) = 0 and (select count(*) from medicines) = 0, 'disabled doctor reads doctors/medicines';
end $$;
reset role;
update profiles set is_active = true where id = 'a2000000-0000-0000-0000-000000000002';

-- ===== 2) plan/schedule history: doctor DA and managing caregiver CY =====
do $$
declare u text; n int;
begin
  foreach u in array array['a2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000003'] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"' || u || '"}', true);
    delete from medication_plans where id = 'f1100000-0000-0000-0000-000000000011';
    get diagnostics n = row_count;
    assert n = 0, u || ' deleted a plan (rows=' || n || ')';
    delete from medication_schedules where id = '51100000-0000-0000-0000-000000000011';
    get diagnostics n = row_count;
    assert n = 0, u || ' deleted a schedule (rows=' || n || ')';
    update medication_schedules set time_of_day = '23:00' where id = '51100000-0000-0000-0000-000000000011';
    get diagnostics n = row_count;
    assert n = 0, u || ' relabelled a schedule (rows=' || n || ')';
    -- unchanged capabilities: edit a plan row, insert a plan row, insert a schedule, call save_plan
    update medication_plans set dose = 'edited-' || right(u, 1) where id = 'f1100000-0000-0000-0000-000000000011';
    get diagnostics n = row_count;
    assert n = 1, u || ' cannot edit a plan (rows=' || n || ')';
    insert into medication_plans (id, patient_id, medicine_id, dose, start_date)
      values (gen_random_uuid(), 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'direct', current_date);
    insert into medication_schedules (plan_id, time_of_day) values ('f1100000-0000-0000-0000-000000000011', '10:00');
    assert save_plan(null, 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'sp', null, current_date, null, null, array['06:00'], 'active') is not null, u || ' save_plan';
    -- they still cannot touch the other patient's plan
    begin
      insert into medication_schedules (plan_id, time_of_day) values ('f2000000-0000-0000-0000-000000000002', '10:00');
      raise exception '% inserted a schedule into another patient plan', u;
    exception when insufficient_privilege then null;
    end;
    reset role;
    -- clean the rows this iteration added, so both users start from the same state
    delete from medication_schedules where time_of_day = '10:00' and plan_id = 'f1100000-0000-0000-0000-000000000011';
  end loop;
end $$;
do $$
begin
  assert exists (select 1 from medication_plans where id = 'f1100000-0000-0000-0000-000000000011')
     and (select time_of_day from medication_schedules where id = '51100000-0000-0000-0000-000000000011') = '09:00', 'history changed';
  assert (select count(*) from medication_logs) = 1, 'a log disappeared';
end $$;

-- CN (can_manage_plan = false) still cannot insert
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000004"}', true);
do $$
begin
  begin
    insert into medication_plans (patient_id, medicine_id, dose, start_date)
      values ('b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'x', current_date);
    raise exception 'CN inserted a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into medication_schedules (plan_id, time_of_day) values ('f1100000-0000-0000-0000-000000000011', '11:00');
    raise exception 'CN inserted a schedule';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- admin still can: update/delete a schedule and delete a plan
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
do $$
declare n int;
begin
  update medication_schedules set time_of_day = '09:30' where id = '51100000-0000-0000-0000-000000000011';
  get diagnostics n = row_count;
  assert n = 1, 'admin cannot update a schedule';
  delete from medication_schedules where id = '51100000-0000-0000-0000-000000000011';
  get diagnostics n = row_count;
  assert n = 1, 'admin cannot delete a schedule';
  delete from medication_plans where id = 'f1100000-0000-0000-0000-000000000011';
  get diagnostics n = row_count;
  assert n = 1, 'admin cannot delete a plan';
end $$;
reset role;

-- ===== 3) log_i: the schedule must belong to the plan =====
insert into medication_plans (id, patient_id, medicine_id, dose, start_date)
  values ('f1200000-0000-0000-0000-000000000012', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'D1c', current_date);
insert into medication_schedules (id, plan_id, time_of_day) values ('51200000-0000-0000-0000-000000000012', 'f1200000-0000-0000-0000-000000000012', '12:00');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-0000-0000-000000000005"}', true);
do $$
begin
  -- valid: own plan + its own schedule
  insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
    values ('f1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', now() + interval '1 hour', 'a5000000-0000-0000-0000-000000000005');
  -- a schedule of another patient's plan
  begin
    insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
      values ('f1000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', now() + interval '2 hours', 'a5000000-0000-0000-0000-000000000005');
    raise exception 'log with a schedule of another patient accepted';
  exception when insufficient_privilege then null;
  end;
  -- a schedule of another plan of the same patient
  begin
    insert into medication_logs (plan_id, schedule_id, scheduled_at, recorded_by)
      values ('f1000000-0000-0000-0000-000000000001', '51200000-0000-0000-0000-000000000012', now() + interval '3 hours', 'a5000000-0000-0000-0000-000000000005');
    raise exception 'log with a schedule of another plan accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select count(*) from medication_logs) = 2, 'log count after log_i checks: ' || (select count(*) from medication_logs);
end $$;

rollback;
