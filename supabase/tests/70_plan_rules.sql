-- save_plan weekday / every-N-days rules (integration.sql, phase 2).
-- Users: AD admin, CN caregiver of P1 (can_manage_plan false). Patient P1. Medicine M1 active.
begin;

insert into auth.users (id, email) values
  ('91000000-0000-0000-0000-000000000001', 'ad2@t'),
  ('94000000-0000-0000-0000-000000000004', 'cn2@t');
update profiles set is_active = true;
insert into user_roles (user_id, role) values
  ('91000000-0000-0000-0000-000000000001', 'admin'),
  ('94000000-0000-0000-0000-000000000004', 'caregiver');
insert into patients (id, user_id, full_name) values
  ('a1000000-0000-0000-0000-000000000001', null, 'P1r');
insert into caregivers (id, user_id, full_name) values
  ('b1000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000004', 'CNr');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'confirmed', false);
insert into medicines (id, generic_name, is_active) values
  ('e9000000-0000-0000-0000-000000000001', 'MR1', true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);

-- ===== the three rule shapes =====
do $$
declare d uuid; w uuid; i uuid;
begin
  -- old 10-argument call form still works and yields a daily plan
  d := save_plan(null, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', '1', null,
                 '2026-11-01', null, null, array['08:00'], 'active');
  w := save_plan(null, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', '1', null,
                 '2026-11-01', null, null, array['08:00', '20:00'], 'active', array[1, 3, 5], null);
  i := save_plan(null, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', '1', null,
                 '2026-11-01', null, null, array['08:00', '20:00'], 'active', null, 2);
  perform set_config('t.d', d::text, true);
  perform set_config('t.w', w::text, true);
  perform set_config('t.i', i::text, true);
end $$;
reset role;
do $$
begin
  assert (select count(*) from medication_schedules where plan_id = current_setting('t.d')::uuid
            and days_of_week is null and interval_days is null) = 1, 'daily: rule columns not null';
  assert (select count(*) from medication_schedules where plan_id = current_setting('t.w')::uuid
            and days_of_week = '{1,3,5}' and interval_days is null) = 2, 'weekdays: both rows must carry {1,3,5}';
  assert (select count(*) from medication_schedules where plan_id = current_setting('t.i')::uuid
            and interval_days = 2 and days_of_week is null) = 2, 'interval: both rows must carry 2';
end $$;

-- ===== invalid rules: 22023 and nothing written =====
select set_config('t.n_plans', (select count(*) from medication_plans)::text, true);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);
do $$
declare
  cases constant text[][] := array[
    -- label, days, interval, end
    array['both',       '{1}',   '2',    null],
    array['empty days', '{}',    null,   null],
    array['day 0',      '{0}',   null,   null],
    array['day 8',      '{8}',   null,   null],
    array['dup days',   '{1,1}', null,   null],
    array['interval 1', null,    '1',    null],
    array['interval 366', null,  '366',  null],
    array['interval + end', null, '2',   '2026-11-30']
  ];
  c text[];
  ok boolean;
begin
  -- 'interval + end' is a VALID rule (end date does not matter to the rule); it must succeed, the others must not
  foreach c slice 1 in array cases loop
    ok := true;
    begin
      perform save_plan(null, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', '1', null,
                        '2026-11-01', c[4]::date, null, array['08:00'], 'active', c[2]::int[], c[3]::int);
    exception when sqlstate '22023' then
      ok := false;
    end;
    if c[1] = 'interval + end' then
      assert ok, 'interval with an end date should be accepted';
    else
      assert not ok, 'rule "' || c[1] || '" should be rejected with 22023';
    end if;
  end loop;
end $$;
reset role;
do $$
begin
  -- 7 rejected calls wrote nothing; the accepted one wrote exactly one plan
  assert (select count(*) from medication_plans) = current_setting('t.n_plans')::int + 1, 'invalid rules left rows behind';
end $$;

-- ===== changing the rule keeps the schedule row and its log; repeating the same call is a no-op =====
do $$
declare s uuid;
begin
  select id into s from medication_schedules where plan_id = current_setting('t.w')::uuid and time_of_day = '08:00';
  perform set_config('t.sched08', s::text, true);
  insert into medication_logs (plan_id, schedule_id, scheduled_at, status)
    values (current_setting('t.w')::uuid, s, '2026-11-02 01:00+00', 'taken');
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  perform save_plan(current_setting('t.w')::uuid, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001',
                    '1', null, '2026-11-01', null, null, array['08:00', '20:00'], 'active', null, 3);
end $$;
reset role;
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);
do $$
begin
  assert (select id from medication_schedules where plan_id = current_setting('t.w')::uuid and time_of_day = '08:00')
         = current_setting('t.sched08')::uuid, 'rule change replaced the schedule row';
  assert (select count(*) from medication_logs where schedule_id = current_setting('t.sched08')::uuid) = 1, 'rule change lost the log';
  assert (select count(*) from medication_schedules where plan_id = current_setting('t.w')::uuid
            and interval_days = 3 and days_of_week is null) = 2, 'rule change not written to every row';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  perform save_plan(current_setting('t.w')::uuid, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001',
                    '1', null, '2026-11-01', null, null, array['08:00', '20:00'], 'active', null, 3);
end $$;
reset role;
do $$
begin
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int,
         'identical save must not write any audit row (plan trigger skips no-op updates, schedules are not updated): delta ' || ((select count(*) from audit_logs) - current_setting('t.n_audit')::int);
end $$;

-- ===== permission is unchanged: caregiver without can_manage_plan still gets 42501 =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"94000000-0000-0000-0000-000000000004"}', true);
do $$
begin
  begin
    perform save_plan(null, 'a1000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', '1', null,
                      '2026-11-01', null, null, array['08:00'], 'active', array[1], null);
    raise exception 'CN: caregiver without can_manage_plan created a plan with a rule';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
