-- save_plan + audit triggers on medication_plans / medication_schedules (integration.sql).
-- Users: AD admin, DA doctor assigned to P1, DB doctor assigned to P2, CN caregiver of P1 (can_manage_plan false),
-- CY caregiver of P1 (can_manage_plan true), DD doctor assigned to P1 but account disabled, PU the patient P1 itself.
-- Medicines: M1, M2 active, MX inactive.
begin;

insert into auth.users (id, email) values
  ('71000000-0000-0000-0000-000000000001', 'ad@t'),
  ('72000000-0000-0000-0000-000000000002', 'da@t'),
  ('73000000-0000-0000-0000-000000000003', 'db@t'),
  ('74000000-0000-0000-0000-000000000004', 'cn@t'),
  ('75000000-0000-0000-0000-000000000005', 'cy@t'),
  ('76000000-0000-0000-0000-000000000006', 'dd@t'),
  ('77000000-0000-0000-0000-000000000007', 'pu@t');
-- profiles exist (on_auth_user_created) and start disabled; DD stays that way.
update profiles set is_active = true where id <> '76000000-0000-0000-0000-000000000006';
insert into user_roles (user_id, role) values
  ('71000000-0000-0000-0000-000000000001', 'admin'),
  ('72000000-0000-0000-0000-000000000002', 'doctor'),
  ('73000000-0000-0000-0000-000000000003', 'doctor'),
  ('74000000-0000-0000-0000-000000000004', 'caregiver'),
  ('75000000-0000-0000-0000-000000000005', 'caregiver'),
  ('76000000-0000-0000-0000-000000000006', 'doctor'),
  ('77000000-0000-0000-0000-000000000007', 'patient');
insert into patients (id, user_id, full_name) values
  ('81000000-0000-0000-0000-000000000001', '77000000-0000-0000-0000-000000000007', 'P1'),
  ('82000000-0000-0000-0000-000000000002', null, 'P2');
insert into doctors (id, user_id, full_name) values
  ('d1000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002', 'DA'),
  ('d2000000-0000-0000-0000-000000000002', '73000000-0000-0000-0000-000000000003', 'DB'),
  ('d3000000-0000-0000-0000-000000000003', '76000000-0000-0000-0000-000000000006', 'DD');
insert into patient_doctors (patient_id, doctor_id) values
  ('81000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001'),
  ('81000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000003'),
  ('82000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002');
insert into caregivers (id, user_id, full_name) values
  ('c1000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000004', 'CN'),
  ('c2000000-0000-0000-0000-000000000002', '75000000-0000-0000-0000-000000000005', 'CY');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('81000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'confirmed', false),
  ('81000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'confirmed', true);
insert into medicines (id, generic_name, is_active) values
  ('e1000000-0000-0000-0000-000000000001', 'M1', true),
  ('e2000000-0000-0000-0000-000000000002', 'M2', true),
  ('e3000000-0000-0000-0000-000000000003', 'MX', false);

-- ===== admin creates a plan: dose/meal trimmed, blank note -> null, 2 schedules, 3 audit rows =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
                   '  1 เม็ด ', ' หลังอาหาร ', '2026-11-01', '2026-11-30', '  ', array['18:00', '08:00'], 'active');
  assert pid is not null, 'create: no id returned';
  perform set_config('t.plan1', pid::text, true);
end $$;
reset role;
do $$
declare
  pid constant uuid := current_setting('t.plan1')::uuid;
  p medication_plans%rowtype;
begin
  select * into p from medication_plans where id = pid;
  assert p.patient_id = '81000000-0000-0000-0000-000000000001' and p.medicine_id = 'e1000000-0000-0000-0000-000000000001', 'create: patient/medicine';
  assert p.dose = '1 เม็ด' and p.meal_relation = 'หลังอาหาร', 'create: dose/meal not trimmed: ' || p.dose || '|' || p.meal_relation;
  assert p.start_date = '2026-11-01' and p.end_date = '2026-11-30' and p.status = 'active', 'create: dates/status';
  assert p.doctor_note is null, 'create: blank note should be null';
  assert p.created_by = '71000000-0000-0000-0000-000000000001', 'create: created_by';
  assert (select count(*) from medication_schedules where plan_id = pid) = 2, 'create: schedule count';
  assert (select count(*) from medication_schedules where plan_id = pid and days_of_week is null and interval_days is null
            and to_char(time_of_day, 'HH24:MI') in ('08:00', '18:00')) = 2, 'create: schedule values';
  assert (select count(*) from audit_logs) = 3, 'create: audit total ' || (select count(*) from audit_logs);
  assert (select count(*) from audit_logs where action = 'medication_plans.insert' and table_name = 'medication_plans'
            and row_id = pid::text and actor = '71000000-0000-0000-0000-000000000001'
            and old_value is null and new_value->>'dose' = '1 เม็ด') = 1, 'create: plan audit row';
  assert (select count(*) from audit_logs a join medication_schedules s on s.id::text = a.row_id
            where a.action = 'medication_schedules.insert' and a.table_name = 'medication_schedules'
              and a.actor = '71000000-0000-0000-0000-000000000001' and a.old_value is null
              and a.new_value->>'plan_id' = pid::text) = 2, 'create: schedule audit rows';
end $$;
select set_config('t.n_plans', (select count(*) from medication_plans)::text, true);

-- ===== who may call: assigned doctor yes, others 42501, and a failed call writes nothing =====
-- DA (assigned to P1) creates a plan for P1
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
  assert pid is not null, 'DA: assigned doctor could not create';
end $$;
reset role;

-- DB (assigned to P2 only): integration.sql section 15 lets any active doctor manage any patient, so P1 is allowed too (that extra plan
-- is deleted right after); P2 plan is reused by the binding tests
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"73000000-0000-0000-0000-000000000003"}', true);
do $$
declare pid uuid;
begin
  perform set_config('t.dbP1', save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active')::text, true);
  pid := save_plan(null, '82000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'Y', null, '2026-11-01', null, null, array['07:00', '19:00'], 'active');
  perform set_config('t.planY', pid::text, true);
end $$;
reset role;
delete from medication_plans where id = current_setting('t.dbP1')::uuid;

-- CN (can_manage_plan = false) refused; CY (true) allowed
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"74000000-0000-0000-0000-000000000004"}', true);
do $$
begin
  begin
    perform save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'CN: caregiver without can_manage_plan created a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan(current_setting('t.plan1')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'CN: caregiver without can_manage_plan edited a plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"75000000-0000-0000-0000-000000000005"}', true);
do $$
begin
  assert save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active') is not null,
    'CY: caregiver with can_manage_plan could not create';
end $$;
reset role;

-- DD (assigned doctor, account disabled), PU (the patient), no uid: all 42501
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"76000000-0000-0000-0000-000000000006"}', true);
do $$
begin
  begin
    perform save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'DD: disabled account created a plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"77000000-0000-0000-0000-000000000007"}', true);
do $$
begin
  begin
    perform save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'PU: patient created a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform save_plan(current_setting('t.plan1')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'PU: patient edited own plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'no uid: created a plan';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role anon;
do $$
begin
  begin
    perform save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['09:00'], 'active');
    raise exception 'anon could call save_plan';
  exception when insufficient_privilege then
    assert sqlerrm like 'permission denied%', 'anon: refused for the wrong reason: ' || sqlerrm;
  end;
end $$;
reset role;
do $$
begin
  -- admin plan1 + DA + DB(P2) + CY = 4 plans; the 8 refused calls left nothing behind
  assert (select count(*) from medication_plans) = current_setting('t.n_plans')::int + 3, 'perm: plan count ' || (select count(*) from medication_plans);
  assert (select count(*) from medication_plans where patient_id = '81000000-0000-0000-0000-000000000001') = 3, 'perm: P1 plan count';
  assert (select dose from medication_plans where id = current_setting('t.plan1')::uuid) = '1 เม็ด', 'perm: refused edit changed plan1';
end $$;
select set_config('t.n_plans', (select count(*) from medication_plans)::text, true);
select set_config('t.n_sched', (select count(*) from medication_schedules)::text, true);
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);

-- ===== validation: each bad input raises 22023 with a Thai message and writes nothing =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare
  c record;
  m1 constant uuid := 'e1000000-0000-0000-0000-000000000001';
  m_dose constant text := 'กรุณาระบุขนาดยา';
  m_dlen constant text := 'ขนาดยาต้องไม่เกิน 100 ตัวอักษร';
  m_meal constant text := 'ความสัมพันธ์กับมื้ออาหารต้องไม่เกิน 50 ตัวอักษร';
  m_note constant text := 'หมายเหตุต้องไม่เกิน 500 ตัวอักษร';
  m_start constant text := 'กรุณาระบุวันเริ่มทานยา';
  m_end constant text := 'วันสิ้นสุดต้องไม่ก่อนวันเริ่ม';
  m_stat constant text := 'สถานะแผนยาไม่ถูกต้อง';
  m_none constant text := 'กรุณาระบุเวลาทานยาอย่างน้อย 1 เวลา';
  m_many constant text := 'กำหนดเวลาทานยาได้ไม่เกิน 12 เวลา';
  m_fmt constant text := 'รูปแบบเวลาต้องเป็น HH:mm (00:00-23:59)';
  m_dup constant text := 'เวลาทานยาซ้ำกัน';
  m_off constant text := 'ยานี้ถูกปิดใช้งาน เลือกยาอื่น';
  m_nomed constant text := 'ไม่พบยาที่เลือก';
begin
  for c in select * from (values
    (''::text,           'a'::text, '2026-11-01'::date, null::date,         null::text, array['08:00'],                'active'::text,  m1, m_dose),
    ('   ',              'a',       '2026-11-01',       null,               null,       array['08:00'],                'active',        m1, m_dose),
    (null,               'a',       '2026-11-01',       null,               null,       array['08:00'],                'active',        m1, m_dose),
    (repeat('ก', 101),   'a',       '2026-11-01',       null,               null,       array['08:00'],                'active',        m1, m_dlen),
    ('1',                repeat('ก', 51), '2026-11-01', null,               null,       array['08:00'],                'active',        m1, m_meal),
    ('1',                'a',       '2026-11-01',       null,               repeat('ก', 501), array['08:00'],          'active',        m1, m_note),
    ('1',                'a',       null,               null,               null,       array['08:00'],                'active',        m1, m_start),
    ('1',                'a',       '2026-11-02',       '2026-11-01',       null,       array['08:00'],                'active',        m1, m_end),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00'],                'x',             m1, m_stat),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00'],                null,            m1, m_stat),
    ('1',                'a',       '2026-11-01',       null,               null,       '{}'::text[],                  'active',        m1, m_none),
    ('1',                'a',       '2026-11-01',       null,               null,       null::text[],                  'active',        m1, m_none),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00', '08:00'],       'active',        m1, m_dup),
    ('1',                'a',       '2026-11-01',       null,               null,       array['8:00'],                 'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,       array['24:00'],                'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:60'],                'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00:00'],             'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,       array[' 08:00'],               'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00', null],          'active',        m1, m_fmt),
    ('1',                'a',       '2026-11-01',       null,               null,
       array['00:00','01:00','02:00','03:00','04:00','05:00','06:00','07:00','08:00','09:00','10:00','11:00','12:00'], 'active', m1, m_many),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00'],                'active', 'e3000000-0000-0000-0000-000000000003', m_off),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00'],                'active', 'e9000000-0000-0000-0000-000000000009', m_nomed),
    ('1',                'a',       '2026-11-01',       null,               null,       array['08:00'],                'active', null::uuid, m_nomed)
  ) as t(dose, meal, sd, ed, note, times, st, med, msg) loop
    begin
      perform save_plan(null, '81000000-0000-0000-0000-000000000001', c.med, c.dose, c.meal, c.sd, c.ed, c.note, c.times, c.st);
      raise exception 'validation: did not raise for (%, %, %, %, %)', c.dose, c.sd, c.ed, c.times, c.st;
    exception when sqlstate '22023' then
      assert sqlerrm = c.msg, 'validation: wrong message "' || sqlerrm || '" for (' || coalesce(left(c.dose, 10), 'null') || ', ' || coalesce(c.times::text, 'null') || ', ' || coalesce(c.st, 'null') || ')';
    end;
  end loop;
  -- unknown patient: the admin passes can_manage_plan, so the function itself refuses
  begin
    perform save_plan(null, '8f000000-0000-0000-0000-00000000000f', m1, '1', null, '2026-11-01', null, null, array['08:00'], 'active');
    raise exception 'validation: unknown patient did not raise';
  exception when sqlstate '22023' then
    assert sqlerrm = 'ไม่พบผู้ป่วย', 'validation: unknown patient message ' || sqlerrm;
  end;
end $$;
reset role;
do $$
begin
  assert (select count(*) from medication_plans) = current_setting('t.n_plans')::int, 'validation: a failed call left a plan';
  assert (select count(*) from medication_schedules) = current_setting('t.n_sched')::int, 'validation: a failed call left a schedule';
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int, 'validation: a failed call left an audit row';
end $$;

-- ===== boundaries are accepted: 100-char dose, 50-char meal, 500-char note, 12 times, 00:00 and 23:59, end = start =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', repeat('ก', 100), repeat('ข', 50), '2026-11-01', '2026-11-01', repeat('ค', 500),
    array['00:00','01:00','02:00','03:00','04:00','05:00','06:00','07:00','08:00','09:00','10:00','23:59'], 'stopped');
  assert (select count(*) from medication_schedules where plan_id = pid) = 12, 'boundary: 12 schedules';
  assert (select status from medication_plans where id = pid) = 'stopped', 'boundary: status';
end $$;
reset role;

-- ===== edit: keep 08:00 (same id; phase 2: it adopts the plan's rule, here daily), drop 18:00 (no logs), add 20:00 =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['08:00', '18:00'], 'active');
  perform set_config('t.planE', pid::text, true);
end $$;
reset role;
do $$
declare pid constant uuid := current_setting('t.planE')::uuid;
begin
  perform set_config('t.s08', (select id::text from medication_schedules where plan_id = pid and time_of_day = '08:00'), true);
  perform set_config('t.s18', (select id::text from medication_schedules where plan_id = pid and time_of_day = '18:00'), true);
  -- a kept schedule with an old rule: the plan-level rule (daily here) replaces it in place, same row id
  update medication_schedules set days_of_week = '{1,3}', interval_days = 2 where id = current_setting('t.s08')::uuid;
end $$;
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  assert save_plan(current_setting('t.planE')::uuid, '81000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002',
                   '2 เม็ด', 'ก่อนอาหาร', '2026-12-01', '2026-12-31', 'โน้ต', array['20:00', '08:00'], 'active') = current_setting('t.planE')::uuid,
    'edit: returned id differs';
end $$;
reset role;
do $$
declare
  pid constant uuid := current_setting('t.planE')::uuid;
  p medication_plans%rowtype;
begin
  select * into p from medication_plans where id = pid;
  assert p.patient_id = '81000000-0000-0000-0000-000000000001', 'edit: patient changed';
  assert p.medicine_id = 'e2000000-0000-0000-0000-000000000002' and p.dose = '2 เม็ด' and p.meal_relation = 'ก่อนอาหาร'
     and p.start_date = '2026-12-01' and p.end_date = '2026-12-31' and p.doctor_note = 'โน้ต' and p.status = 'active', 'edit: plan fields';
  assert p.created_by = '71000000-0000-0000-0000-000000000001', 'edit: created_by changed';
  assert exists (select 1 from medication_schedules where id = current_setting('t.s08')::uuid and plan_id = pid
                   and days_of_week is null and interval_days is null), 'edit: 08:00 row not kept (same id, now daily)';
  assert not exists (select 1 from medication_schedules where id = current_setting('t.s18')::uuid), 'edit: 18:00 row not removed';
  assert (select count(*) from medication_schedules where plan_id = pid) = 2, 'edit: schedule count';
  assert exists (select 1 from medication_schedules where plan_id = pid and time_of_day = '20:00' and days_of_week is null and interval_days is null), 'edit: 20:00 not added';
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int + 4, 'edit: audit delta ' || ((select count(*) from audit_logs) - current_setting('t.n_audit')::int);
  assert (select count(*) from audit_logs where row_id = pid::text and action = 'medication_plans.update'
            and old_value->>'dose' = '1' and new_value->>'dose' = '2 เม็ด' and actor = '72000000-0000-0000-0000-000000000002') = 1, 'edit: plan.update audit';
  assert (select count(*) from audit_logs where action = 'medication_schedules.delete' and row_id = current_setting('t.s18')
            and old_value->>'time_of_day' = '18:00:00' and new_value is null) = 1, 'edit: schedule.delete audit';
  assert (select count(*) from audit_logs where action = 'medication_schedules.insert' and new_value->>'time_of_day' = '20:00:00'
            and new_value->>'plan_id' = pid::text) = 1, 'edit: schedule.insert audit';
  -- two update audit rows for the kept schedule: the fixture's own rule change and save_plan resetting it to the plan rule (daily)
  assert (select count(*) from audit_logs where action = 'medication_schedules.update' and row_id = current_setting('t.s08')) = 2, 'edit: kept row audit count';
end $$;

-- ===== Review Focus: removing a time that has logs is refused and changes nothing =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'L', null, '2026-11-01', null, null, array['08:00', '18:00'], 'active');
  perform set_config('t.planL', pid::text, true);
end $$;
reset role;
do $$
declare pid constant uuid := current_setting('t.planL')::uuid; s uuid;
begin
  perform set_config('t.l08', (select id::text from medication_schedules where plan_id = pid and time_of_day = '08:00'), true);
  perform set_config('t.l18', (select id::text from medication_schedules where plan_id = pid and time_of_day = '18:00'), true);
  insert into medication_logs (plan_id, schedule_id, scheduled_at, status)
    values (pid, current_setting('t.l18')::uuid, '2026-11-02 18:00+07', 'taken');
end $$;
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  begin
    perform save_plan(current_setting('t.planL')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
                      'ห้ามเปลี่ยน', 'x', '2026-12-01', null, 'x', array['08:00', '20:00'], 'stopped');
    raise exception 'logs: removing a logged time did not raise';
  exception when sqlstate 'P0001' then
    assert sqlerrm = 'ไม่สามารถเอาเวลา 18:00 ออกได้ เพราะมีบันทึกการทานยาแล้ว กรุณาหยุดแผนนี้แล้วสร้างแผนใหม่แทน', 'logs: wrong message: ' || sqlerrm;
  end;
end $$;
reset role;
do $$
declare pid constant uuid := current_setting('t.planL')::uuid;
begin
  assert (select dose from medication_plans where id = pid) = 'L' and (select status from medication_plans where id = pid) = 'active'
     and (select start_date from medication_plans where id = pid) = '2026-11-01', 'logs: plan changed by a refused call';
  assert (select count(*) from medication_schedules where plan_id = pid) = 2
     and exists (select 1 from medication_schedules where id = current_setting('t.l08')::uuid)
     and exists (select 1 from medication_schedules where id = current_setting('t.l18')::uuid), 'logs: schedules changed by a refused call';
  assert not exists (select 1 from medication_schedules where plan_id = pid and time_of_day = '20:00'), 'logs: 20:00 was added';
  assert (select count(*) from medication_logs where plan_id = pid and schedule_id = current_setting('t.l18')::uuid) = 1, 'logs: log lost';
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int, 'logs: refused call left audit rows';
end $$;

-- stopping the plan (times unchanged) works; adding a time next to a logged one works; logs survive
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  perform save_plan(current_setting('t.planL')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'L', null, '2026-11-01', null, null, array['08:00', '18:00'], 'stopped');
  perform save_plan(current_setting('t.planL')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'L', null, '2026-11-01', null, null, array['08:00', '18:00', '21:00'], 'stopped');
end $$;
reset role;
do $$
declare pid constant uuid := current_setting('t.planL')::uuid;
begin
  assert (select status from medication_plans where id = pid) = 'stopped', 'logs: plan not stopped';
  assert (select count(*) from medication_schedules where plan_id = pid) = 3, 'logs: 21:00 not added';
  assert (select count(*) from medication_logs where plan_id = pid) = 1, 'logs: log lost after stop/add';
end $$;
-- removing times with no logs next to a logged one is fine (08:00 and 21:00 go, logged 18:00 stays)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  perform save_plan(current_setting('t.planL')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'L', null, '2026-11-01', null, null, array['18:00'], 'stopped');
end $$;
reset role;
do $$
declare pid constant uuid := current_setting('t.planL')::uuid;
begin
  assert (select count(*) from medication_schedules where plan_id = pid) = 1
     and exists (select 1 from medication_schedules where id = current_setting('t.l18')::uuid), 'logs: unlogged times not removed';
  assert (select count(*) from medication_logs where plan_id = pid) = 1, 'logs: log lost after removing unlogged times';
end $$;

-- ===== plan/patient binding: a plan id of another patient cannot be reached through an allowed p_patient_id =====
-- planY belongs to P2. DA manages P1 only.
select set_config('t.y_before', (select to_jsonb(p)::text || (select string_agg(s.id::text, ',' order by s.id) from medication_schedules s where s.plan_id = p.id)
  from medication_plans p where p.id = current_setting('t.planY')::uuid), true);
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  begin
    perform save_plan(current_setting('t.planY')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'hijack', null, '2026-11-01', null, null, array['03:00'], 'stopped');
    raise exception 'binding: DA edited P2 plan through p_patient_id = P1';
  exception when insufficient_privilege then
    assert sqlerrm = 'ไม่พบแผนยาของผู้ป่วยนี้', 'binding: wrong message ' || sqlerrm;
  end;
  -- same answer for a plan id that does not exist (no existence oracle)
  begin
    perform save_plan('9f000000-0000-0000-0000-00000000000f', '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1', null, '2026-11-01', null, null, array['03:00'], 'active');
    raise exception 'binding: unknown plan id did not raise';
  exception when insufficient_privilege then
    assert sqlerrm = 'ไม่พบแผนยาของผู้ป่วยนี้', 'binding: unknown plan message ' || sqlerrm;
  end;
end $$;
reset role;
-- even the admin cannot move a plan to another patient
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  begin
    perform save_plan(current_setting('t.planY')::uuid, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'hijack', null, '2026-11-01', null, null, array['03:00'], 'stopped');
    raise exception 'binding: admin moved a plan to another patient';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select to_jsonb(p)::text || (select string_agg(s.id::text, ',' order by s.id) from medication_schedules s where s.plan_id = p.id)
            from medication_plans p where p.id = current_setting('t.planY')::uuid) = current_setting('t.y_before'), 'binding: P2 plan or schedules changed';
  assert (select patient_id from medication_plans where id = current_setting('t.planY')::uuid) = '82000000-0000-0000-0000-000000000002', 'binding: P2 plan moved';
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int, 'binding: refused calls left audit rows';
end $$;
-- the right doctor, with the right patient, may edit it
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"73000000-0000-0000-0000-000000000003"}', true);
do $$
begin
  assert save_plan(current_setting('t.planY')::uuid, '82000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'Y2', null, '2026-11-01', null, null, array['07:00', '19:00'], 'active') = current_setting('t.planY')::uuid,
    'binding: DB could not edit own patient plan';
  -- and DB cannot reach a P1 plan by naming P2 (binding)
  begin
    perform save_plan(current_setting('t.plan1')::uuid, '82000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'hijack', null, '2026-11-01', null, null, array['03:00'], 'active');
    raise exception 'binding: DB edited P1 plan via P2';
  exception when insufficient_privilege then null;
  end;
  -- (naming P1 is allowed since section 15: any doctor manages any patient, so only the binding check applies)
end $$;
reset role;
do $$
begin
  assert (select dose from medication_plans where id = current_setting('t.planY')::uuid) = 'Y2', 'binding: DB edit not applied';
  assert (select dose from medication_plans where id = current_setting('t.plan1')::uuid) = '1 เม็ด', 'binding: P1 plan changed by DB';
end $$;

-- ===== medicine rule: a NEW medicine must be active; a plan may keep its current medicine after it is deactivated =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pid uuid;
begin
  pid := save_plan(null, '81000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'M', null, '2026-11-01', null, null, array['05:00'], 'active');
  perform set_config('t.planM', pid::text, true);
end $$;
reset role;
update medicines set is_active = false where id = 'e2000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001"}', true);
do $$
declare pm constant uuid := current_setting('t.planM')::uuid;
begin
  -- keeping the now-inactive M2 is allowed (stopping a plan must stay possible)
  perform save_plan(pm, '81000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'M-kept', null, '2026-11-01', null, null, array['05:00'], 'stopped');
  -- switching to an inactive medicine is not
  begin
    perform save_plan(pm, '81000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', 'M-x', null, '2026-11-01', null, null, array['05:00'], 'active');
    raise exception 'medicine: switched to inactive MX';
  exception when sqlstate '22023' then null;
  end;
  -- switch to active M1, then back to inactive M2: no longer "current", so refused
  perform save_plan(pm, '81000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'M-1', null, '2026-11-01', null, null, array['05:00'], 'active');
  begin
    perform save_plan(pm, '81000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'M-back', null, '2026-11-01', null, null, array['05:00'], 'active');
    raise exception 'medicine: switched back to inactive M2';
  exception when sqlstate '22023' then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select dose from medication_plans where id = current_setting('t.planM')::uuid) = 'M-1'
     and (select medicine_id from medication_plans where id = current_setting('t.planM')::uuid) = 'e1000000-0000-0000-0000-000000000001', 'medicine: final state';
end $$;

-- ===== audit triggers outside save_plan: no uid (SQL editor / service) is allowed, no-op updates are skipped, deletes cascade-audited =====
select set_config('request.jwt.claims', '', true);
select set_config('t.n_audit', (select count(*) from audit_logs)::text, true);
do $$
declare pid constant uuid := current_setting('t.planL')::uuid;
begin
  update medication_plans set dose = dose where id = pid;
  assert (select count(*) from audit_logs) = current_setting('t.n_audit')::int, 'audit: no-op update was audited';
  update medication_plans set dose = 'L-sql' where id = pid;
  assert (select count(*) from audit_logs where action = 'medication_plans.update' and row_id = pid::text and actor is null
            and old_value->>'dose' = 'L' and new_value->>'dose' = 'L-sql') = 1, 'audit: null-actor update row';
  delete from medication_plans where id = pid;   -- cascades to schedules and logs
  assert (select count(*) from audit_logs where action = 'medication_plans.delete' and row_id = pid::text and actor is null
            and old_value->>'dose' = 'L-sql' and new_value is null) = 1, 'audit: plan.delete row';
  assert (select count(*) from audit_logs where action = 'medication_schedules.delete' and row_id = current_setting('t.l18')
            and old_value->>'plan_id' = pid::text and actor is null) = 1, 'audit: cascaded schedule.delete row';
  assert not exists (select 1 from medication_logs where plan_id = pid), 'audit: cascade left logs';
end $$;

-- a plain authenticated user without rights still cannot read audit_logs (admin only), and the trigger function is not callable
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"72000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  assert (select count(*) from audit_logs) = 0, 'audit: doctor can read audit_logs';
  begin
    perform audit_plan_change();
    raise exception 'audit: trigger function callable by authenticated';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
