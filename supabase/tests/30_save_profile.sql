-- save_my_profile (integration.sql).
-- Users: S1 + S2 are active patients (rows P1, P2), S3 is active with no patient row, S4 has a patient row but is disabled.
begin;
-- this test keeps profile and patient names apart on purpose: switch the name sync (integration.sql 20) off for it
alter table profiles disable trigger profiles_name_sync;
alter table patients disable trigger patients_name_sync;

insert into auth.users (id, email, phone, phone_confirmed_at) values
  ('51000000-0000-0000-0000-000000000001', 's1@t', '66811111111', now()),
  ('52000000-0000-0000-0000-000000000002', 's2@t', '66822222222', now()),
  ('53000000-0000-0000-0000-000000000003', 's3@t', '66833333333', now()),
  ('54000000-0000-0000-0000-000000000004', 's4@t', '66844444444', now());
-- profiles exist (on_auth_user_created) and start disabled; S4 stays that way.
update profiles set is_active = true, full_name = 'Profile old'
  where id in ('51000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000003');
update profiles set full_name = 'Profile old' where id = '54000000-0000-0000-0000-000000000004';
insert into user_roles (user_id, role) values
  ('51000000-0000-0000-0000-000000000001', 'patient'),
  ('52000000-0000-0000-0000-000000000002', 'patient'),
  ('54000000-0000-0000-0000-000000000004', 'patient');
insert into patients (id, user_id, full_name, age, conditions, nickname, phone) values
  ('61000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 'Name old 1', 30, 'เดิม', 'old1', '0811111111'),
  ('62000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000002', 'Name old 2', 40, 'เดิม', 'old2', '0822222222'),
  ('64000000-0000-0000-0000-000000000004', '54000000-0000-0000-0000-000000000004', 'Name old 4', 50, 'เดิม', 'old4', '0844444444');

-- ===== validation: every bad input raises 22023 with a Thai message naming the field, and writes nothing =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-0000-0000-000000000001"}', true);
do $$
declare
  c record;
  m_nick constant text := 'ชื่อเล่นต้องมี 1-50 ตัวอักษร';
  m_name constant text := 'ชื่อ-นามสกุลต้องมี 1-100 ตัวอักษร';
  m_age constant text := 'อายุต้องอยู่ระหว่าง 1-120 ปี';
  m_cond constant text := 'กรุณาระบุโรคประจำตัวอย่างน้อย 1 รายการ';
  m_ver constant text := 'ไม่พบเวอร์ชันความยินยอม';
begin
  for c in select * from (values
    ('',               'ชื่อ', 35, '{เบาหวาน}'::text[],   '2026-11', m_nick),
    ('   ',            'ชื่อ', 35, '{เบาหวาน}'::text[],   '2026-11', m_nick),
    (null,             'ชื่อ', 35, '{เบาหวาน}'::text[],   '2026-11', m_nick),
    (repeat('ก', 51),  'ชื่อ', 35, '{เบาหวาน}'::text[],   '2026-11', m_nick),
    ('เล่น', '',                35, '{เบาหวาน}'::text[],   '2026-11', m_name),
    ('เล่น', ' ',               35, '{เบาหวาน}'::text[],   '2026-11', m_name),
    ('เล่น', null,              35, '{เบาหวาน}'::text[],   '2026-11', m_name),
    ('เล่น', repeat('ก', 101),  35, '{เบาหวาน}'::text[],   '2026-11', m_name),
    ('เล่น', 'ชื่อ', 0,    '{เบาหวาน}'::text[],   '2026-11', m_age),
    ('เล่น', 'ชื่อ', 121,  '{เบาหวาน}'::text[],   '2026-11', m_age),
    ('เล่น', 'ชื่อ', -5,   '{เบาหวาน}'::text[],   '2026-11', m_age),
    ('เล่น', 'ชื่อ', null, '{เบาหวาน}'::text[],   '2026-11', m_age),
    ('เล่น', 'ชื่อ', 35, '{}'::text[],            '2026-11', m_cond),
    ('เล่น', 'ชื่อ', 35, null,                    '2026-11', m_cond),
    ('เล่น', 'ชื่อ', 35, '{" "}'::text[],         '2026-11', m_cond),
    ('เล่น', 'ชื่อ', 35, '{เบาหวาน,""}'::text[],  '2026-11', m_cond),
    ('เล่น', 'ชื่อ', 35, array['เบาหวาน', null],  '2026-11', m_cond),
    ('เล่น', 'ชื่อ', 35, '{เบาหวาน}'::text[],     '',        m_ver),
    ('เล่น', 'ชื่อ', 35, '{เบาหวาน}'::text[],     '  ',      m_ver),
    ('เล่น', 'ชื่อ', 35, '{เบาหวาน}'::text[],     null,      m_ver)
  ) as t(n, f, a, cond, v, msg) loop
    begin
      perform save_my_profile(c.n, c.f, c.a, c.cond, c.v);
      raise exception 'validation: did not raise for (%, %, %, %, %)', c.n, c.f, c.a, c.cond, c.v;
    exception when sqlstate '22023' then
      assert sqlerrm = c.msg, 'validation: wrong message "' || sqlerrm || '" for (' || coalesce(c.n, 'null') || ', ' || coalesce(c.f, 'null') || ', ' || coalesce(c.a::text, 'null') || ')';
    end;
  end loop;
  -- boundary values are accepted: 50-char nickname, 100-char name, age 1 and 120
  perform save_my_profile(repeat('ก', 50), repeat('ข', 100), 1, '{เบาหวาน}', '2026-11');
  perform save_my_profile(' เล่น ', ' ชื่อ ', 120, '{เบาหวาน}', '2026-11');
end $$;
reset role;
-- the two boundary calls above are the only writes; undo them so "nothing changed" is checkable below
do $$
begin
  assert (select count(*) from consents where user_id = '51000000-0000-0000-0000-000000000001') = 2, 'boundary: expected 2 consents';
  assert (select count(*) from audit_logs where action = 'save_my_profile') = 2, 'boundary: expected 2 audit rows';
end $$;
delete from consents where user_id = '51000000-0000-0000-0000-000000000001';
delete from audit_logs where action = 'save_my_profile';
update patients set nickname = 'old1', full_name = 'Name old 1', age = 30, conditions = 'เดิม', profile_completed_at = null
  where id = '61000000-0000-0000-0000-000000000001';
update profiles set full_name = 'Profile old' where id = '51000000-0000-0000-0000-000000000001';

-- ===== re-run the bad inputs in one go, then prove the failed calls changed nothing =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  begin perform save_my_profile('', 'ชื่อ', 35, '{เบาหวาน}', '2026-11'); raise exception 'nick'; exception when sqlstate '22023' then null; end;
  begin perform save_my_profile('เล่น', repeat('ก', 101), 35, '{เบาหวาน}', '2026-11'); raise exception 'name'; exception when sqlstate '22023' then null; end;
  begin perform save_my_profile('เล่น', 'ชื่อ', 121, '{เบาหวาน}', '2026-11'); raise exception 'age'; exception when sqlstate '22023' then null; end;
  begin perform save_my_profile('เล่น', 'ชื่อ', 35, '{" "}', '2026-11'); raise exception 'cond'; exception when sqlstate '22023' then null; end;
  begin perform save_my_profile('เล่น', 'ชื่อ', 35, '{เบาหวาน}', ''); raise exception 'ver'; exception when sqlstate '22023' then null; end;
end $$;
reset role;
do $$
declare p patients%rowtype;
begin
  select * into p from patients where id = '61000000-0000-0000-0000-000000000001';
  assert p.nickname = 'old1' and p.full_name = 'Name old 1' and p.age = 30 and p.conditions = 'เดิม' and p.profile_completed_at is null,
    'failed validation changed the patient row';
  assert (select full_name from profiles where id = '51000000-0000-0000-0000-000000000001') = 'Profile old', 'failed validation changed profiles.full_name';
  assert not exists (select 1 from consents where user_id = '51000000-0000-0000-0000-000000000001'), 'failed validation wrote a consent';
  assert not exists (select 1 from audit_logs where action = 'save_my_profile'), 'failed validation wrote an audit row';
end $$;

-- ===== success: S1 saves; values are trimmed, conditions joined =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  perform save_my_profile('  น้องเอ  ', '  สมชาย ใจดี ', 35, array[' เบาหวาน ', 'โรคไต'], '2026-11');
end $$;
reset role;
do $$
declare
  u constant uuid := '51000000-0000-0000-0000-000000000001';
  p patients%rowtype;
  a audit_logs%rowtype;
begin
  select * into p from patients where id = '61000000-0000-0000-0000-000000000001';
  assert p.nickname = 'น้องเอ', 'save: nickname ' || coalesce(p.nickname, 'null');
  assert p.full_name = 'สมชาย ใจดี', 'save: full_name ' || p.full_name;
  assert p.age = 35, 'save: age';
  assert p.conditions = 'เบาหวาน, โรคไต', 'save: conditions ' || coalesce(p.conditions, 'null');
  assert p.profile_completed_at is not null, 'save: profile_completed_at null';
  assert p.user_id = u and p.phone = '0811111111', 'save: user_id/phone changed';
  assert (select full_name from profiles where id = u) = 'สมชาย ใจดี', 'save: profiles.full_name';
  assert (select is_active from profiles where id = u), 'save: profile deactivated';
  assert (select count(*) from user_roles where user_id = u) = 1, 'save: roles changed';
  assert (select count(*) from consents where user_id = u and version = '2026-11' and given_by = u and withdrawn_at is null) = 1, 'save: consent row';
  select * into a from audit_logs where action = 'save_my_profile';
  assert a.actor = u and a.table_name = 'patients' and a.row_id = '61000000-0000-0000-0000-000000000001', 'save: audit actor/target';
  assert a.old_value->>'nickname' = 'old1' and a.new_value->>'nickname' = 'น้องเอ', 'save: audit nickname';
  assert a.old_value->>'full_name' = 'Name old 1' and a.new_value->>'full_name' = 'สมชาย ใจดี', 'save: audit full_name';
  assert a.old_value->>'age' = '30' and a.new_value->>'age' = '35', 'save: audit age';
  assert a.old_value->>'conditions' = 'เดิม' and a.new_value->>'conditions' = 'เบาหวาน, โรคไต', 'save: audit conditions';
  assert a.old_value ? 'profile_completed_at' and a.old_value->>'profile_completed_at' is null, 'save: audit old profile_completed_at';
  assert a.new_value->>'profile_completed_at' is not null, 'save: audit new profile_completed_at';
  assert (select count(*) from audit_logs where action = 'save_my_profile') = 1, 'save: audit row count';
  -- S1's call never touches P2 or P4 (or their profiles)
  assert (select (nickname, full_name, age, conditions, profile_completed_at) from patients where id = '62000000-0000-0000-0000-000000000002')
         is not distinct from row('old2'::text, 'Name old 2'::text, 40, 'เดิม'::text, null::timestamptz), 'cross: P2 changed';
  assert (select (nickname, full_name, age, conditions, profile_completed_at) from patients where id = '64000000-0000-0000-0000-000000000004')
         is not distinct from row('old4'::text, 'Name old 4'::text, 50, 'เดิม'::text, null::timestamptz), 'cross: P4 changed';
  assert (select count(*) from profiles where full_name = 'Profile old') = 3, 'cross: another profile changed';
  assert not exists (select 1 from consents where user_id <> u), 'cross: consent for another user';
end $$;

-- ===== second call: updates again and adds a second consent (history), audit old value is the first save =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  perform save_my_profile('เอ2', 'สมชาย', 36, array['ความดัน'], '2026-12');
end $$;
reset role;
do $$
declare u constant uuid := '51000000-0000-0000-0000-000000000001';
begin
  assert (select (nickname, age, conditions) from patients where id = '61000000-0000-0000-0000-000000000001')
         is not distinct from row('เอ2'::text, 36, 'ความดัน'::text), 'second: values not updated';
  assert (select count(*) from consents where user_id = u) = 2, 'second: consent history';
  assert exists (select 1 from consents where user_id = u and version = '2026-12'), 'second: new consent version';
  assert (select count(*) from audit_logs where action = 'save_my_profile') = 2, 'second: audit count';
  assert (select old_value->>'nickname' from audit_logs where action = 'save_my_profile' order by id desc limit 1) = 'น้องเอ', 'second: audit old nickname';
end $$;

-- ===== S2 saves: S1's row stays as it was =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"52000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  perform save_my_profile('บี', 'สมหญิง', 41, array['หัวใจ'], '2026-11');
end $$;
reset role;
do $$
begin
  assert (select (nickname, full_name, age, conditions) from patients where id = '62000000-0000-0000-0000-000000000002')
         is not distinct from row('บี'::text, 'สมหญิง'::text, 41, 'หัวใจ'::text), 'S2: own row not updated';
  assert (select (nickname, age, conditions) from patients where id = '61000000-0000-0000-0000-000000000001')
         is not distinct from row('เอ2'::text, 36, 'ความดัน'::text), 'S2: changed S1 row';
  assert (select user_id from patients where id = '62000000-0000-0000-0000-000000000002') = '52000000-0000-0000-0000-000000000002', 'S2: user_id';
end $$;

-- ===== no patient row (S3): 42501, nothing written =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"53000000-0000-0000-0000-000000000003"}', true);
do $$
begin
  begin
    perform save_my_profile('เล่น', 'ชื่อ', 35, '{เบาหวาน}', '2026-11');
    raise exception 'S3: no patient row did not raise';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from consents where user_id = '53000000-0000-0000-0000-000000000003'), 'S3: consent written';
  assert (select full_name from profiles where id = '53000000-0000-0000-0000-000000000003') = 'Profile old', 'S3: profile changed';
  assert not exists (select 1 from audit_logs where actor = '53000000-0000-0000-0000-000000000003'), 'S3: audit written';
end $$;

-- ===== disabled account (S4): 42501, nothing changes =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"54000000-0000-0000-0000-000000000004"}', true);
do $$
begin
  begin
    perform save_my_profile('เล่น', 'ชื่อ', 35, '{เบาหวาน}', '2026-11');
    raise exception 'S4: disabled account did not raise';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select (nickname, full_name, age, conditions, profile_completed_at) from patients where id = '64000000-0000-0000-0000-000000000004')
         is not distinct from row('old4'::text, 'Name old 4'::text, 50, 'เดิม'::text, null::timestamptz), 'S4: patient row changed';
  assert (select full_name from profiles where id = '54000000-0000-0000-0000-000000000004') = 'Profile old', 'S4: profile changed';
  assert not (select is_active from profiles where id = '54000000-0000-0000-0000-000000000004'), 'S4: re-enabled';
  assert not exists (select 1 from consents where user_id = '54000000-0000-0000-0000-000000000004'), 'S4: consent written';
  assert not exists (select 1 from audit_logs where actor = '54000000-0000-0000-0000-000000000004'), 'S4: audit written';
end $$;

-- ===== no auth.uid(): 42501 =====
set local role authenticated;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform save_my_profile('เล่น', 'ชื่อ', 35, '{เบาหวาน}', '2026-11');
    raise exception 'no uid did not raise';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ===== anon cannot call at all =====
reset role;
set local role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform save_my_profile('เล่น', 'ชื่อ', 35, '{เบาหวาน}', '2026-11');
    raise exception 'anon could call save_my_profile';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
