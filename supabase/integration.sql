-- App integration on top of schema.sql + security_fixes.sql. Safe to re-run.

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
