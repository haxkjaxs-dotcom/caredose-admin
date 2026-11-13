-- App integration on top of schema.sql + security_fixes.sql. Safe to re-run.
-- Run order: schema.sql -> security_fixes.sql -> integration.sql. Re-running security_fixes.sql afterwards is also safe
-- (its guard_admin_columns is identical to section 3 here); the test harness does exactly that.

-- 1) New patient columns (filled in by the app)
alter table patients add column if not exists nickname text,
                     add column if not exists profile_completed_at timestamptz;

-- 2) Phone normalisation: digits only, a leading 66 becomes 0 (0812345678 = 66812345678 = +66 81-234-5678)
create or replace function norm_phone(p text) returns text
language sql immutable strict as $$
  select case when d like '66%' then '0' || substr(d, 3) else d end
  from (select regexp_replace(p, '[^0-9]', '', 'g') as d) s
$$;

-- 3) guard_admin_columns: same rules as security_fixes.sql, but only for direct API calls.
--    Inside claim_my_patient (security definer) current_user is the function owner, so the trigger lets it set user_id.
--    The guard must be SECURITY INVOKER: in a security definer function current_user is always the owner,
--    so the current_user test would never be true and the guard would stop blocking direct API updates.
create or replace function guard_admin_columns() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and not has_role('admin') and current_user in ('authenticated', 'anon') then
    -- nested ifs on purpose: plpgsql resolves new.is_active when it plans the expression, and patients has no is_active
    if tg_table_name = 'doctors' then
      if new.user_id is distinct from old.user_id or new.is_active is distinct from old.is_active then
        raise exception 'เฉพาะ Admin เท่านั้นที่แก้ไขข้อมูลนี้ได้' using errcode = '42501';
      end if;
    elsif tg_table_name = 'patients' then
      if new.user_id is distinct from old.user_id then
        raise exception 'เฉพาะ Admin เท่านั้นที่แก้ไขข้อมูลนี้ได้' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end
$$;

-- 4) claim_my_patient: link the signed-in account to the one unowned patient row with the same phone.
--    The phone comes from auth.users (never from the client).
create or replace function claim_my_patient() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  raw_phone text;
  np text;
  pid uuid;
  ids uuid[];
  pname text;
begin
  if uid is null then
    raise exception 'ต้องเข้าสู่ระบบก่อน' using errcode = '42501';
  end if;
  -- one claim per account at a time, so a double tap cannot race itself
  perform pg_advisory_xact_lock(hashtextextended('claim_my_patient:' || uid::text, 0));

  -- already linked: return it and touch nothing (an admin-disabled account must stay disabled)
  select id into pid from patients where user_id = uid order by id limit 1;
  if pid is not null then
    return pid;
  end if;

  -- privileged accounts never claim: claiming activates the profile, which would revive an admin-disabled doctor/caregiver/admin
  if exists (select 1 from user_roles where user_id = uid and role <> 'patient') then
    raise exception 'บัญชีนี้ผูกกับผู้ป่วยไม่ได้' using errcode = '42501';
  end if;

  -- only a phone confirmed by OTP counts
  select phone into raw_phone from auth.users where id = uid and phone_confirmed_at is not null;
  np := norm_phone(raw_phone);
  if coalesce(np, '') = '' then
    raise exception 'บัญชีนี้ไม่มีเบอร์โทรที่ยืนยันแล้ว' using errcode = '42501';
  end if;

  select array_agg(id) into ids from (
    select id from patients where user_id is null and norm_phone(phone) = np for update
  ) s;
  if ids is null then
    return null;
  end if;
  if array_length(ids, 1) > 1 then
    raise exception 'เบอร์ซ้ำในระบบ' using errcode = 'P0001';
  end if;
  pid := ids[1];

  update patients set user_id = uid where id = pid and user_id is null returning full_name into pname;
  insert into user_roles (user_id, role) values (uid, 'patient') on conflict do nothing;
  insert into profiles (id, phone, full_name, is_active) values (uid, np, pname, true)
    on conflict (id) do update set is_active = true, phone = excluded.phone, full_name = excluded.full_name;
  insert into audit_logs (actor, action, table_name, row_id, new_value)
    values (uid, 'claim_patient', 'patients', pid::text, jsonb_build_object('user_id', uid, 'phone', np));
  return pid;
end
$$;
revoke execute on function claim_my_patient() from public, anon;
grant execute on function claim_my_patient() to authenticated;

-- 5) save_my_profile: the signed-in patient fills in their own profile and gives consent.
--    Security definer, so it bypasses RLS and guard_admin_columns: it only ever touches the patients row where
--    user_id = auth.uid() (never an id from the caller) and never writes user_id, roles, doctors or profiles.is_active.
--    Every input is validated before the first write, so a failed call changes nothing.
create or replace function save_my_profile(p_nickname text, p_full_name text, p_age int, p_conditions text[], p_consent_version text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  pid uuid;
  nick text := regexp_replace(p_nickname, '^\s+|\s+$', '', 'g');
  fname text := regexp_replace(p_full_name, '^\s+|\s+$', '', 'g');
  ver text := regexp_replace(p_consent_version, '^\s+|\s+$', '', 'g');
  conds text[];
  old_p patients%rowtype;
  now_ts timestamptz := now();
begin
  if uid is null or not is_active_user() then
    raise exception 'ต้องเข้าสู่ระบบด้วยบัญชีที่เปิดใช้งาน' using errcode = '42501';
  end if;
  select * into old_p from patients where user_id = uid order by id limit 1 for update;
  if not found then
    raise exception 'ไม่พบข้อมูลผู้ป่วยของบัญชีนี้' using errcode = '42501';
  end if;
  pid := old_p.id;

  if coalesce(char_length(nick), 0) not between 1 and 50 then
    raise exception 'ชื่อเล่นต้องมี 1-50 ตัวอักษร' using errcode = '22023';
  end if;
  if coalesce(char_length(fname), 0) not between 1 and 100 then
    raise exception 'ชื่อ-นามสกุลต้องมี 1-100 ตัวอักษร' using errcode = '22023';
  end if;
  if p_age is null or p_age not between 1 and 120 then
    raise exception 'อายุต้องอยู่ระหว่าง 1-120 ปี' using errcode = '22023';
  end if;
  select array_agg(t order by ord) into conds
    from (select regexp_replace(e, '^\s+|\s+$', '', 'g') as t, ord from unnest(p_conditions) with ordinality as u(e, ord)) s;
  if conds is null or exists (select 1 from unnest(conds) c where c is null or c = '') then
    raise exception 'กรุณาระบุโรคประจำตัวอย่างน้อย 1 รายการ' using errcode = '22023';
  end if;
  if coalesce(ver, '') = '' then
    raise exception 'ไม่พบเวอร์ชันความยินยอม' using errcode = '22023';
  end if;

  update patients set nickname = nick, full_name = fname, age = p_age,
         conditions = array_to_string(conds, ', '), profile_completed_at = now_ts
    where id = pid;
  update profiles set full_name = fname where id = uid;
  insert into consents (user_id, version, given_by) values (uid, ver, uid);
  insert into audit_logs (actor, action, table_name, row_id, old_value, new_value)
    values (uid, 'save_my_profile', 'patients', pid::text,
      jsonb_build_object('nickname', old_p.nickname, 'full_name', old_p.full_name, 'age', old_p.age,
                         'conditions', old_p.conditions, 'profile_completed_at', old_p.profile_completed_at),
      jsonb_build_object('nickname', nick, 'full_name', fname, 'age', p_age,
                         'conditions', array_to_string(conds, ', '), 'profile_completed_at', now_ts));
end
$$;
revoke execute on function save_my_profile(text, text, int, text[], text) from public, anon;
grant execute on function save_my_profile(text, text, int, text[], text) to authenticated;

-- 6) Audit trigger for plan changes. Browsers cannot write audit_logs (security_fixes #8), so the trigger writes as definer.
--    auth.uid() is null for SQL-editor / service-role work: audit_logs.actor is nullable, so that is recorded as a null actor.
--    No-op updates are skipped. The trigger never raises on its own and writes only audit_logs (which has no trigger), so no recursion.
create or replace function audit_plan_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into audit_logs (actor, action, table_name, row_id, new_value)
      values (auth.uid(), tg_table_name || '.insert', tg_table_name, new.id::text, to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    if to_jsonb(old) is distinct from to_jsonb(new) then
      insert into audit_logs (actor, action, table_name, row_id, old_value, new_value)
        values (auth.uid(), tg_table_name || '.update', tg_table_name, new.id::text, to_jsonb(old), to_jsonb(new));
    end if;
  else
    insert into audit_logs (actor, action, table_name, row_id, old_value)
      values (auth.uid(), tg_table_name || '.delete', tg_table_name, old.id::text, to_jsonb(old));
  end if;
  return null;
end
$$;
-- only the trigger machinery calls it; privileges are checked at CREATE TRIGGER, not when it fires
revoke execute on function audit_plan_change() from public, anon, authenticated;
drop trigger if exists medication_plans_audit on medication_plans;
create trigger medication_plans_audit after insert or update or delete on medication_plans
  for each row execute function audit_plan_change();
drop trigger if exists medication_schedules_audit on medication_schedules;
create trigger medication_schedules_audit after insert or update or delete on medication_schedules
  for each row execute function audit_plan_change();

-- 7) save_plan: create or edit a medication plan and its times in one transaction.
--    Security definer, so it bypasses RLS: the permission checks below run before the first write and are the only gate.
--    Tables touched: patients (existence check), medicines (read), medication_plans (read+lock, insert/update),
--    medication_schedules (lock, insert, delete), medication_logs (existence check only). Audit rows come from the triggers above.
--    Every input is validated before the first write, and any later raise rolls the whole call back.
--    Phase 2 rule: p_days_of_week (ISO 1=Mon..7=Sun) or p_interval_days (2..365, counted from p_start), never both; null/null = every day.
--    The rule belongs to the plan, so every schedule row of the plan carries the same one.
drop function if exists save_plan(uuid, uuid, uuid, text, text, date, date, text, text[], text);
create or replace function save_plan(p_plan_id uuid, p_patient_id uuid, p_medicine_id uuid, p_dose text, p_meal_relation text,
                                     p_start date, p_end date, p_note text, p_times text[], p_status text,
                                     p_days_of_week int[] default null, p_interval_days int default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_dose text := regexp_replace(p_dose, '^\s+|\s+$', '', 'g');
  v_meal text := nullif(regexp_replace(p_meal_relation, '^\s+|\s+$', '', 'g'), '');
  v_note text := nullif(regexp_replace(p_note, '^\s+|\s+$', '', 'g'), '');
  old_p medication_plans%rowtype;
  pid uuid;
  med_active boolean;
  ts time[];
  blocked text;
begin
  if auth.uid() is null or not is_active_user() or p_patient_id is null or not can_manage_plan(p_patient_id) then
    raise exception 'ไม่มีสิทธิ์จัดการแผนยาของผู้ป่วยรายนี้' using errcode = '42501';
  end if;
  if not exists (select 1 from patients where id = p_patient_id) then
    raise exception 'ไม่พบผู้ป่วย' using errcode = '22023';
  end if;

  -- an existing plan must belong to the patient the caller was authorised for (else a doctor of X could edit Y's plan).
  -- Same answer for "no such plan", so plan ids cannot be probed. The row lock serialises concurrent saves of one plan.
  if p_plan_id is not null then
    select * into old_p from medication_plans where id = p_plan_id and patient_id = p_patient_id for update;
    if not found then
      raise exception 'ไม่พบแผนยาของผู้ป่วยนี้' using errcode = '42501';
    end if;
  end if;

  if coalesce(v_dose, '') = '' then
    raise exception 'กรุณาระบุขนาดยา' using errcode = '22023';
  end if;
  if char_length(v_dose) > 100 then
    raise exception 'ขนาดยาต้องไม่เกิน 100 ตัวอักษร' using errcode = '22023';
  end if;
  if char_length(v_meal) > 50 then
    raise exception 'ความสัมพันธ์กับมื้ออาหารต้องไม่เกิน 50 ตัวอักษร' using errcode = '22023';
  end if;
  if char_length(v_note) > 500 then
    raise exception 'หมายเหตุต้องไม่เกิน 500 ตัวอักษร' using errcode = '22023';
  end if;
  if p_start is null then
    raise exception 'กรุณาระบุวันเริ่มทานยา' using errcode = '22023';
  end if;
  if p_end is not null and p_end < p_start then
    raise exception 'วันสิ้นสุดต้องไม่ก่อนวันเริ่ม' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('active', 'stopped') then
    raise exception 'สถานะแผนยาไม่ถูกต้อง' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_times), 0) = 0 then
    raise exception 'กรุณาระบุเวลาทานยาอย่างน้อย 1 เวลา' using errcode = '22023';
  end if;
  if cardinality(p_times) > 12 then
    raise exception 'กำหนดเวลาทานยาได้ไม่เกิน 12 เวลา' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_times) t where t is null or t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
    raise exception 'รูปแบบเวลาต้องเป็น HH:mm (00:00-23:59)' using errcode = '22023';
  end if;
  if (select count(distinct t) from unnest(p_times) t) <> cardinality(p_times) then
    raise exception 'เวลาทานยาซ้ำกัน' using errcode = '22023';
  end if;
  -- compare times as time values, never as text
  select array_agg(t::time) into ts from unnest(p_times) t;

  if p_days_of_week is not null and p_interval_days is not null then
    raise exception 'เลือกกฎได้เพียงแบบเดียว (เฉพาะวัน หรือ ทุก N วัน)' using errcode = '22023';
  end if;
  if p_days_of_week is not null and (
       cardinality(p_days_of_week) = 0
       or exists (select 1 from unnest(p_days_of_week) d where d is null or d not between 1 and 7)
       or (select count(distinct d) from unnest(p_days_of_week) d) <> cardinality(p_days_of_week)) then
    raise exception 'วันที่ทานต้องเป็น 1-7 ไม่ซ้ำกัน และเลือกอย่างน้อย 1 วัน' using errcode = '22023';
  end if;
  if p_interval_days is not null and p_interval_days not between 2 and 365 then
    raise exception 'ทุก N วัน: N ต้องอยู่ระหว่าง 2 ถึง 365' using errcode = '22023';
  end if;

  -- medicine: a NEW choice must be active; a plan may keep its current medicine after it was deactivated
  -- (otherwise an old plan could no longer be edited or stopped)
  select is_active into med_active from medicines where id = p_medicine_id;
  if not found then
    raise exception 'ไม่พบยาที่เลือก' using errcode = '22023';
  end if;
  if not med_active and not (p_plan_id is not null and old_p.medicine_id = p_medicine_id) then
    raise exception 'ยานี้ถูกปิดใช้งาน เลือกยาอื่น' using errcode = '22023';
  end if;

  if p_plan_id is not null then
    -- lock the schedules that would go, THEN look for logs in a fresh statement: a log insert takes a key-share lock
    -- on its schedule, so no log can slip in between this check and the delete (the cascade would erase it)
    perform 1 from medication_schedules where plan_id = p_plan_id and time_of_day <> all (ts) for update;
    select string_agg(to_char(s.time_of_day, 'HH24:MI'), ', ' order by s.time_of_day) into blocked
      from medication_schedules s
      where s.plan_id = p_plan_id and s.time_of_day <> all (ts)
        and exists (select 1 from medication_logs l where l.schedule_id = s.id);
    if blocked is not null then
      raise exception 'ไม่สามารถเอาเวลา % ออกได้ เพราะมีบันทึกการทานยาแล้ว กรุณาหยุดแผนนี้แล้วสร้างแผนใหม่แทน', blocked;
    end if;

    update medication_plans set medicine_id = p_medicine_id, dose = v_dose, meal_relation = v_meal, start_date = p_start,
           end_date = p_end, status = p_status, doctor_note = v_note
      where id = p_plan_id;
    pid := p_plan_id;
    delete from medication_schedules where plan_id = pid and time_of_day <> all (ts);
    -- kept rows adopt the new rule in place (their logs hang off the row id); untouched rows write nothing
    update medication_schedules set days_of_week = p_days_of_week, interval_days = p_interval_days
      where plan_id = pid and (days_of_week, interval_days) is distinct from (p_days_of_week, p_interval_days);
  else
    insert into medication_plans (patient_id, medicine_id, dose, meal_relation, start_date, end_date, status, doctor_note, created_by)
      values (p_patient_id, p_medicine_id, v_dose, v_meal, p_start, p_end, p_status, v_note, auth.uid())
      returning id into pid;
  end if;

  insert into medication_schedules (plan_id, time_of_day, days_of_week, interval_days)
    select pid, t, p_days_of_week, p_interval_days from unnest(ts) t
    where not exists (select 1 from medication_schedules s where s.plan_id = pid and s.time_of_day = t);
  return pid;
end
$$;
revoke execute on function save_plan(uuid, uuid, uuid, text, text, date, date, text, text[], text, int[], int) from public, anon;
grant execute on function save_plan(uuid, uuid, uuid, text, text, date, date, text, text[], text, int[], int) to authenticated;

-- 8) doctors / medicines: readable only by an active account. schema.sql used `using (true)`, so a brand-new phone
--    sign-up (profile disabled by default) could read every doctor's name, department and phone with the public key.
--    Active patients still read both (the plan list embeds medicines and doctor names).
drop policy if exists doctors_r on doctors;
create policy doctors_r on doctors for select to authenticated using (is_active_user());
drop policy if exists med_r on medicines;
create policy med_r on medicines for select to authenticated using (is_active_user());

-- 9) Plan history. schema.sql gave plan_w / sched_w FOR ALL to everyone who can manage a plan, so a doctor could delete a plan
--    (cascading away its adherence logs) or relabel a schedule straight over REST, which save_plan refuses to do.
--    Now: doctors / managing caregivers still insert and edit plans and insert schedules; only admin deletes plans and
--    deletes/edits schedules. save_plan is security definer and unaffected (it only deletes schedules that have no logs).
drop policy if exists plan_w on medication_plans;
drop policy if exists plan_i on medication_plans;
drop policy if exists plan_u on medication_plans;
drop policy if exists plan_d on medication_plans;
create policy plan_i on medication_plans for insert to authenticated with check (can_manage_plan(patient_id));
create policy plan_u on medication_plans for update to authenticated
  using (can_manage_plan(patient_id)) with check (can_manage_plan(patient_id));
create policy plan_d on medication_plans for delete to authenticated using (has_role('admin'));

drop policy if exists sched_w on medication_schedules;
drop policy if exists sched_i on medication_schedules;
drop policy if exists sched_u on medication_schedules;
drop policy if exists sched_d on medication_schedules;
create policy sched_i on medication_schedules for insert to authenticated
  with check (exists (select 1 from medication_plans p where p.id = plan_id and can_manage_plan(p.patient_id)));
create policy sched_u on medication_schedules for update to authenticated
  using (has_role('admin')) with check (has_role('admin'));
create policy sched_d on medication_schedules for delete to authenticated using (has_role('admin'));

-- a log must reference a schedule of its own plan (before: any schedule id the caller could see).
-- A RESTRICTIVE policy is ANDed with log_i from security_fixes #7. It is a separate policy, not an edit of log_i, so
-- re-running security_fixes.sql (which drops and recreates log_i) cannot silently remove it.
drop policy if exists log_i_same_plan on medication_logs;
create policy log_i_same_plan on medication_logs as restrictive for insert to authenticated
  with check (exists (select 1 from medication_schedules s where s.id = schedule_id and s.plan_id = medication_logs.plan_id));

-- 8) Phase 2: admin messages to a linked patient.
--    notifications has no insert policy on purpose (browsers cannot write it); this security definer function is the only
--    way in. Note the existing notif_u policy lets the owner edit any column of their own rows (title/body too), not just
--    `read`. Harmless for a message the owner already holds; tighten when the inbox matters beyond a demo.
create or replace function send_notification(p_patient_id uuid, p_title text, p_body text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_title text := regexp_replace(p_title, '^\s+|\s+$', '', 'g');
  v_body text := regexp_replace(p_body, '^\s+|\s+$', '', 'g');
  v_user uuid;
  nid uuid;
begin
  if auth.uid() is null or not is_active_user() or not has_role('admin') then
    raise exception 'ไม่มีสิทธิ์ส่งข้อความ' using errcode = '42501';
  end if;
  if coalesce(v_title, '') = '' then
    raise exception 'กรุณากรอกหัวข้อ' using errcode = '22023';
  end if;
  if char_length(v_title) > 100 then
    raise exception 'หัวข้อต้องไม่เกิน 100 ตัวอักษร' using errcode = '22023';
  end if;
  if coalesce(v_body, '') = '' then
    raise exception 'กรุณากรอกข้อความ' using errcode = '22023';
  end if;
  if char_length(v_body) > 500 then
    raise exception 'ข้อความต้องไม่เกิน 500 ตัวอักษร' using errcode = '22023';
  end if;
  select user_id into v_user from patients where id = p_patient_id;
  if not found then
    raise exception 'ไม่พบผู้ป่วย' using errcode = '22023';
  end if;
  if v_user is null then
    raise exception 'ผู้ป่วยรายนี้ยังไม่ได้เชื่อมแอป' using errcode = '22023';
  end if;
  insert into notifications (user_id, type, title, body, patient_id)
    values (v_user, 'admin_message', v_title, v_body, p_patient_id)
    returning id into nid;
  insert into audit_logs (actor, action, table_name, row_id, new_value)
    values (auth.uid(), 'send_notification', 'notifications', nid::text,
            jsonb_build_object('patient_id', p_patient_id, 'title', v_title));
  return nid;
end
$$;
revoke execute on function send_notification(uuid, text, text) from public, anon;
grant execute on function send_notification(uuid, text, text) to authenticated;

-- Realtime: let the app hear new rows. RLS (notif_r) still decides who receives which row.
-- No-op where the publication does not exist (PGlite tests) or the table is already published (re-runs).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table notifications;
  end if;
end $$;

-- 10) medicines: med_w was FOR ALL to admin or doctor, so a doctor could delete a medicine over REST.
--     Now doctors still insert and edit; only admin deletes (a medicine used by a plan is refused by the FK anyway).
drop policy if exists med_w on medicines;
drop policy if exists med_i on medicines;
drop policy if exists med_u on medicines;
drop policy if exists med_d on medicines;
create policy med_i on medicines for insert to authenticated with check (has_role('admin') or has_role('doctor'));
create policy med_u on medicines for update to authenticated
  using (has_role('admin') or has_role('doctor')) with check (has_role('admin') or has_role('doctor'));
create policy med_d on medicines for delete to authenticated using (has_role('admin'));

-- 11) Admin deletes a user account. Deleting auth.users cascades profile + roles. The account's own doctors / caregivers
--     row goes with it (else an orphan card with user_id null stays in the lists); patient assignments / links to that row
--     cascade, appointments keep their row with doctor_id null. Patients and logs keep their rows (user_id set null).
--     Never your own account, so the app cannot be left without an admin. Only admin (a doctor cannot delete accounts).
create or replace function delete_user(p_user_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not is_active_user() or not has_role('admin') then
    raise exception 'ไม่มีสิทธิ์ลบบัญชี' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'ลบบัญชีของตัวเองไม่ได้' using errcode = '22023';
  end if;
  delete from doctors where user_id = p_user_id;
  delete from caregivers where user_id = p_user_id;
  delete from auth.users where id = p_user_id;
  if not found then
    raise exception 'ไม่พบบัญชี' using errcode = '22023';
  end if;
  insert into audit_logs (actor, action, table_name, row_id, old_value)
    values (auth.uid(), 'delete_user', 'auth.users', p_user_id::text, null);
end
$$;
revoke execute on function delete_user(uuid) from public, anon;
grant execute on function delete_user(uuid) to authenticated;

-- 12) Who may change accounts on the Users page. schema.sql let any admin do anything (roles_w FOR ALL, profiles_u), including
--     giving themselves a role. Now:
--      * Admin changes any account's role and enabled/disabled status and may delete accounts, but never their OWN
--        (no self-granting, no self-lock-out: one admin always remains);
--      * ผู้ดูแลภาพรวม (an active doctor) sees the account list and may change role (caregiver / patient only) and enabled status
--        of NON-staff accounts. Admin / doctor accounts, and their own, are read-only to them. They cannot delete accounts
--        (delete_user stays admin only) and cannot grant admin / doctor;
--      * a doctor may also create the caregivers row for an account they just made a caregiver.
--     Roles are never updated in place (the app inserts the new role, then deletes the others).
create or replace function is_staff_user(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles where user_id = uid and role in ('admin', 'doctor'))
$$;
revoke execute on function is_staff_user(uuid) from public, anon;
grant execute on function is_staff_user(uuid) to authenticated;

drop policy if exists profiles_r on profiles;
create policy profiles_r on profiles for select to authenticated
  using (id = auth.uid() or has_role('admin') or (has_role('doctor') and is_active_user()));
drop policy if exists roles_r on user_roles;
create policy roles_r on user_roles for select to authenticated
  using (user_id = auth.uid() or has_role('admin') or (has_role('doctor') and is_active_user()));

drop policy if exists roles_w on user_roles;
drop policy if exists roles_i on user_roles;
drop policy if exists roles_d on user_roles;
create policy roles_i on user_roles for insert to authenticated with check (
  user_id <> auth.uid() and (has_role('admin')
    or (has_role('doctor') and is_active_user() and role in ('caregiver', 'patient') and not is_staff_user(user_id))));
create policy roles_d on user_roles for delete to authenticated using (
  user_id <> auth.uid() and (has_role('admin') or (has_role('doctor') and is_active_user() and not is_staff_user(user_id))));

drop policy if exists profiles_u on profiles;
create policy profiles_u on profiles for update to authenticated
  using (id <> auth.uid() and (has_role('admin') or (has_role('doctor') and is_active_user() and not is_staff_user(id))))
  with check (id <> auth.uid() and (has_role('admin') or (has_role('doctor') and is_active_user() and not is_staff_user(id))));

drop policy if exists cg_i_doctor on caregivers;
create policy cg_i_doctor on caregivers for insert to authenticated
  with check (has_role('doctor') and is_active_user() and user_id is not null and not is_staff_user(user_id));

-- 13) Security review 2026-11-11.
--  a) medication_logs: log_u's WITH CHECK only pinned recorded_by, so a patient / caregiver could re-point their log at another
--     schedule (log_r already blocks other patients' plans) or push scheduled_at forward, which re-opens the 24h edit window for
--     ever. A non-admin direct API update may now change the dose result only, never which dose the log is about.
--     SECURITY INVOKER for the same reason as guard_admin_columns (#3). The app's sync upsert re-sends the same values, so it passes.
create or replace function guard_log_columns() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and not has_role('admin') and current_user in ('authenticated', 'anon')
     and (new.plan_id, new.schedule_id, new.scheduled_at) is distinct from (old.plan_id, old.schedule_id, old.scheduled_at) then
    raise exception 'แก้ไขแผนยา เวลานัดทานยา หรือรอบยาของบันทึกนี้ไม่ได้' using errcode = '42501';
  end if;
  return new;
end
$$;
drop trigger if exists medication_logs_guard on medication_logs;
create trigger medication_logs_guard before update on medication_logs for each row execute function guard_log_columns();

--  b) patients: patients_u_doctor used can_manage_plan, so a relative allowed to manage plans could also rewrite the patient's
--     chart (drug allergies, conditions, phone) over REST. Now only an assigned, active doctor edits it (Admin has patients_w).
drop policy if exists patients_u_doctor on patients;
create policy patients_u_doctor on patients for update to authenticated
  using (is_active_user() and exists (select 1 from patient_doctors pd join doctors d on d.id = pd.doctor_id
                                      where pd.patient_id = patients.id and pd.active and d.user_id = auth.uid()))
  with check (is_active_user() and exists (select 1 from patient_doctors pd join doctors d on d.id = pd.doctor_id
                                           where pd.patient_id = patients.id and pd.active and d.user_id = auth.uid()));

-- 14) Security review 2026-11-12. Both guards are SECURITY INVOKER and act on direct API calls only (see #3), so save_plan and
--     other security definer functions are unaffected.
--  a) medication_plans: plan_u let a doctor / managing caregiver move a plan (and with it every adherence log) to another patient,
--     and created_by was whatever the client sent, so the record could name someone else as its author.
--     Now a direct insert is stamped with the caller, and only Admin may change patient_id or created_by.
create or replace function guard_plan_columns() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.created_by := auth.uid();
    elsif not has_role('admin')
          and (new.patient_id, new.created_by) is distinct from (old.patient_id, old.created_by) then
      raise exception 'ย้ายแผนยาไปผู้ป่วยอื่นหรือแก้ผู้สร้างแผนไม่ได้' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;
drop trigger if exists medication_plans_guard on medication_plans;
create trigger medication_plans_guard before insert or update on medication_plans
  for each row execute function guard_plan_columns();

--  b) appointments: appt_confirm (the patient's own appointment) had no column limit, so a patient could move the time or change
--     the doctor, place and reason. Someone who cannot manage the patient's plan may now change only status and note.
create or replace function guard_appt_columns() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and current_user in ('authenticated', 'anon') and not can_manage_plan(old.patient_id)
     and (new.patient_id, new.doctor_id, new.appointment_at, new.place, new.department, new.reason)
         is distinct from (old.patient_id, old.doctor_id, old.appointment_at, old.place, old.department, old.reason) then
    raise exception 'ผู้ป่วยยืนยันหรือแก้หมายเหตุนัดหมายได้เท่านั้น' using errcode = '42501';
  end if;
  return new;
end
$$;
drop trigger if exists appointments_guard on appointments;
create trigger appointments_guard before update on appointments for each row execute function guard_appt_columns();


-- 15) ผู้ดูแลภาพรวม (an active doctor) works on EVERY patient, like Admin. Before, a doctor saw only the patients assigned to them,
--     so patients Admin added (and their plans, logs, appointments) were invisible to a doctor.
--     * can_see_patient / can_manage_plan now accept any doctor (both already require an active account); patient lists, plans,
--       medication logs and appointments all follow these two functions;
--     * a doctor reads every caregiver, edits caregivers rows of non-staff accounts and links / unlinks them to patients.
--       Deleting a caregiver stays Admin only (cg_w).
create or replace function can_see_patient(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_active_user() and (
    has_role('admin') or has_role('doctor')
    or exists (select 1 from patients p where p.id = pid and p.user_id = auth.uid())
    or exists (select 1 from patient_caregivers pc join caregivers c on c.id = pc.caregiver_id
               where pc.patient_id = pid and pc.status = 'confirmed' and pc.revoked_at is null
                 and c.user_id = auth.uid())
  )
$$;

create or replace function can_manage_plan(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_active_user() and (
    has_role('admin') or has_role('doctor')
    or exists (select 1 from patient_caregivers pc join caregivers c on c.id = pc.caregiver_id
               where pc.patient_id = pid and pc.status = 'confirmed' and pc.revoked_at is null
                 and pc.can_manage_plan and c.user_id = auth.uid())
  )
$$;

drop policy if exists cg_r_doctor on caregivers;
create policy cg_r_doctor on caregivers for select to authenticated using (has_role('doctor') and is_active_user());
drop policy if exists cg_u_doctor on caregivers;
create policy cg_u_doctor on caregivers for update to authenticated
  using (has_role('doctor') and is_active_user() and (user_id is null or not is_staff_user(user_id)))
  with check (has_role('doctor') and is_active_user() and (user_id is null or not is_staff_user(user_id)));
drop policy if exists pc_i_doctor on patient_caregivers;
create policy pc_i_doctor on patient_caregivers for insert to authenticated with check (has_role('doctor') and is_active_user());
drop policy if exists pc_u_doctor on patient_caregivers;
create policy pc_u_doctor on patient_caregivers for update to authenticated
  using (has_role('doctor') and is_active_user()) with check (has_role('doctor') and is_active_user());
drop policy if exists pc_d_doctor on patient_caregivers;
create policy pc_d_doctor on patient_caregivers for delete to authenticated using (has_role('doctor') and is_active_user());

-- 16) Security review 2026-11-12. cg_u_doctor (#15) let a doctor change caregivers.user_id, so a relative's row, with every confirmed
--     patient link and can_manage_plan right on it, could be handed to another account (the relative silently lost access).
--     Who a record belongs to stays Admin only, as for doctors / patients (#3). A separate trigger, so guard_admin_columns stays
--     identical in security_fixes.sql and here. SECURITY INVOKER for the same reason as #3; inserts are not affected.
create or replace function guard_caregiver_owner() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and not has_role('admin') and current_user in ('authenticated', 'anon')
     and new.user_id is distinct from old.user_id then
    raise exception 'เฉพาะ Admin เท่านั้นที่เปลี่ยนบัญชีของญาติ/ผู้ดูแลได้' using errcode = '42501';
  end if;
  return new;
end
$$;
drop trigger if exists caregivers_guard on caregivers;
create trigger caregivers_guard before update on caregivers for each row execute function guard_caregiver_owner();

-- 17) Security review 2026-11-13.
--  a) A link the patient revoked (pc_revoke) stays revoked. pc_u_doctor / pc_d_doctor (#15) let a doctor set it back to confirmed,
--     or delete it and insert a fresh confirmed one, overriding the patient's decision. A doctor may still revoke a live link,
--     but only Admin (pc_w) re-confirms or removes a revoked one.
drop policy if exists pc_u_doctor on patient_caregivers;
create policy pc_u_doctor on patient_caregivers for update to authenticated
  using (has_role('doctor') and is_active_user() and status <> 'revoked') with check (has_role('doctor') and is_active_user());
drop policy if exists pc_d_doctor on patient_caregivers;
create policy pc_d_doctor on patient_caregivers for delete to authenticated
  using (has_role('doctor') and is_active_user() and status <> 'revoked');

--  b) follow_ups.by_name was free text, so anyone allowed to write a note (fu_i) could sign it with a doctor's name.
--     A direct API insert now takes the author's own profile name. SECURITY INVOKER: the caller reads their own profile (profiles_r).
create or replace function stamp_follow_up_author() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and current_user in ('authenticated', 'anon') then
    new.by_name := coalesce((select nullif(trim(coalesce(full_name, phone)), '') from profiles where id = auth.uid()), 'ไม่ระบุชื่อ');
  end if;
  return new;
end
$$;
drop trigger if exists follow_ups_author on follow_ups;
create trigger follow_ups_author before insert on follow_ups for each row execute function stamp_follow_up_author();
