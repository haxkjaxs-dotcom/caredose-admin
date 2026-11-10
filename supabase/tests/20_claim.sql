-- norm_phone + claim_my_patient (integration.sql). auth.users.phone is stored without '+', e.g. 66812345678.
-- Users: U1..U3 claim their patient row (stored as 0812.., +66 .., 66..), U4 has no patient, U5 has two rows with
-- the same phone, U6's number belongs to a row owned by U7, U8 has no phone, U9 has an empty phone (and a patient row with '').
-- Also safe to paste into the Supabase SQL Editor (after 50_rls_check.sql): one transaction that ends in rollback, every assertion
-- is scoped to its own fixture ids, and the fixtures use only auth.users columns that exist on a real project. If a real patient
-- or account already uses one of the fake numbers (e.g. 0812345678) it fails loudly and nothing is kept. "Success. No rows returned" = passed.
begin;

-- ===== norm_phone =====
do $$
begin
  assert norm_phone('0812345678') = '0812345678', 'norm: 0812345678';
  assert norm_phone('66812345678') = '0812345678', 'norm: 66812345678';
  assert norm_phone('+66 81-234-5678') = '0812345678', 'norm: +66 81-234-5678';
  assert norm_phone('081-234-5678') = '0812345678', 'norm: 081-234-5678';
  assert norm_phone('') = '', 'norm: empty string';
  assert norm_phone(null) is null, 'norm: null';
end $$;

insert into auth.users (id, email, phone, phone_confirmed_at) values
  ('a1000000-0000-0000-0000-000000000001', 'u1@t', '66812345678', now()),
  ('a2000000-0000-0000-0000-000000000002', 'u2@t', '66823456789', now()),
  ('a3000000-0000-0000-0000-000000000003', 'u3@t', '66834567890', now()),
  ('a4000000-0000-0000-0000-000000000004', 'u4@t', '66845678901', now()),
  ('a5000000-0000-0000-0000-000000000005', 'u5@t', '66856789012', now()),
  ('a6000000-0000-0000-0000-000000000006', 'u6@t', '66867890123', now()),
  ('a7000000-0000-0000-0000-000000000007', 'u7@t', '66878901234', now()),
  ('a8000000-0000-0000-0000-000000000008', 'u8@t', null, now()),
  ('a9000000-0000-0000-0000-000000000009', 'u9@t', '', now()),
  ('ad000000-0000-0000-0000-00000000000d', 'admin@t', '66800000000', now());
-- profiles exist (on_auth_user_created) and start disabled; the admin is active.
insert into user_roles (user_id, role) values ('ad000000-0000-0000-0000-00000000000d', 'admin');
update profiles set is_active = true where id = 'ad000000-0000-0000-0000-00000000000d';

insert into patients (id, user_id, full_name, phone) values
  ('b1000000-0000-0000-0000-000000000001', null, 'Patient 1', '0812345678'),
  ('b2000000-0000-0000-0000-000000000002', null, 'Patient 2', '+66 82-345-6789'),
  ('b3000000-0000-0000-0000-000000000003', null, 'Patient 3', '66834567890'),
  ('b5000000-0000-0000-0000-00000000005a', null, 'Patient 5a', '0856789012'),
  ('b5000000-0000-0000-0000-00000000005b', null, 'Patient 5b', '085-678-9012'),
  ('b6000000-0000-0000-0000-000000000006', 'a7000000-0000-0000-0000-000000000007', 'Patient 6 (owned by U7)', '0867890123'),
  ('b9000000-0000-0000-0000-000000000009', null, 'Patient 9 (empty phone)', ''),
  ('b0000000-0000-0000-0000-000000000000', null, 'Patient no phone', null);

-- ===== claim by U1 (phone stored as 0812345678) =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
do $$
declare r uuid;
begin
  r := claim_my_patient();
  assert r = 'b1000000-0000-0000-0000-000000000001', 'claim U1: returned ' || coalesce(r::text, 'null');
end $$;
reset role;
do $$
declare u constant uuid := 'a1000000-0000-0000-0000-000000000001';
begin
  assert (select user_id from patients where id = 'b1000000-0000-0000-0000-000000000001') = u, 'claim U1: user_id not set';
  assert exists (select 1 from user_roles where user_id = u and role = 'patient'), 'claim U1: no patient role';
  assert (select is_active from profiles where id = u), 'claim U1: profile not activated';
  assert (select phone from profiles where id = u) = '0812345678', 'claim U1: profiles.phone ' || coalesce((select phone from profiles where id = u), 'null');
  assert (select count(*) from audit_logs where action = 'claim_patient' and actor = u
            and row_id = 'b1000000-0000-0000-0000-000000000001') = 1, 'claim U1: audit row missing';
end $$;

-- ===== idempotent: second call returns the same id, no second audit row =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  assert claim_my_patient() = 'b1000000-0000-0000-0000-000000000001', 'idempotent: different id';
end $$;
reset role;
do $$
begin
  assert (select count(*) from audit_logs where action = 'claim_patient' and actor = 'a1000000-0000-0000-0000-000000000001') = 1,
    'idempotent: second call wrote another audit row';
end $$;

-- ===== Review Focus 3: admin disables U1, claiming again must not re-enable =====
update profiles set is_active = false where id = 'a1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
do $$
begin
  assert claim_my_patient() = 'b1000000-0000-0000-0000-000000000001', 'disabled: different id';
end $$;
reset role;
do $$
begin
  assert not (select is_active from profiles where id = 'a1000000-0000-0000-0000-000000000001'),
    'disabled: claim_my_patient re-enabled an admin-disabled account';
  assert (select count(*) from audit_logs where action = 'claim_patient' and actor = 'a1000000-0000-0000-0000-000000000001') = 1,
    'disabled: claim wrote another audit row';
end $$;

-- ===== Review Focus 1: phone stored as '+66 82-345-6789' (U2) and '66834567890' (U3) =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  assert claim_my_patient() = 'b2000000-0000-0000-0000-000000000002', 'claim U2 (+66 82-345-6789)';
end $$;
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000003"}', true);
do $$
begin
  assert claim_my_patient() = 'b3000000-0000-0000-0000-000000000003', 'claim U3 (66834567890)';
end $$;
reset role;
do $$
begin
  assert (select user_id from patients where id = 'b2000000-0000-0000-0000-000000000002') = 'a2000000-0000-0000-0000-000000000002', 'U2 user_id';
  assert (select user_id from patients where id = 'b3000000-0000-0000-0000-000000000003') = 'a3000000-0000-0000-0000-000000000003', 'U3 user_id';
  assert (select is_active from profiles where id = 'a2000000-0000-0000-0000-000000000002'), 'U2 not activated';
  assert (select is_active from profiles where id = 'a3000000-0000-0000-0000-000000000003'), 'U3 not activated';
  assert exists (select 1 from user_roles where user_id = 'a2000000-0000-0000-0000-000000000002' and role = 'patient'), 'U2 role';
  assert exists (select 1 from user_roles where user_id = 'a3000000-0000-0000-0000-000000000003' and role = 'patient'), 'U3 role';
  assert (select count(*) from audit_logs where action = 'claim_patient' and actor in
            ('a2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000003')) = 2, 'U2/U3 audit rows';
end $$;

-- ===== no matching patient: null, nothing changes =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000004"}', true);
do $$
begin
  assert claim_my_patient() is null, 'U4: expected null';
end $$;
reset role;
do $$
declare u constant uuid := 'a4000000-0000-0000-0000-000000000004';
begin
  assert not exists (select 1 from user_roles where user_id = u), 'U4: role added';
  assert not (select is_active from profiles where id = u), 'U4: profile activated';
  assert not exists (select 1 from audit_logs where actor = u), 'U4: audit written';
end $$;

-- ===== Review Focus 2: two unowned rows with the same phone: P0001 and neither is bound =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-0000-0000-000000000005"}', true);
do $$
begin
  begin
    perform claim_my_patient();
    raise exception 'U5: duplicate phone did not raise';
  exception when sqlstate 'P0001' then
    assert sqlerrm = 'เบอร์ซ้ำในระบบ', 'U5: wrong message ' || sqlerrm;
  end;
end $$;
reset role;
do $$
declare u constant uuid := 'a5000000-0000-0000-0000-000000000005';
begin
  assert (select count(*) from patients where phone in ('0856789012', '085-678-9012') and user_id is not null) = 0, 'U5: a duplicate row was bound';
  assert not exists (select 1 from user_roles where user_id = u), 'U5: role added';
  assert not (select is_active from profiles where id = u), 'U5: profile activated';
  assert not exists (select 1 from audit_logs where actor = u), 'U5: audit written';
end $$;

-- ===== matching row already has another owner: null, owner unchanged =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a6000000-0000-0000-0000-000000000006"}', true);
do $$
begin
  assert claim_my_patient() is null, 'U6: expected null (row owned by U7)';
end $$;
reset role;
do $$
declare u constant uuid := 'a6000000-0000-0000-0000-000000000006';
begin
  assert (select user_id from patients where id = 'b6000000-0000-0000-0000-000000000006') = 'a7000000-0000-0000-0000-000000000007', 'U6: stole U7 row';
  assert not exists (select 1 from user_roles where user_id = u), 'U6: role added';
  assert not (select is_active from profiles where id = u), 'U6: profile activated';
end $$;

-- ===== no phone / empty phone on the account: 42501, never matches rows with null or empty phone =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a8000000-0000-0000-0000-000000000008"}', true);
do $$
begin
  begin
    perform claim_my_patient();
    raise exception 'U8: null phone did not raise';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"a9000000-0000-0000-0000-000000000009"}', true);
do $$
begin
  begin
    perform claim_my_patient();
    raise exception 'U9: empty phone did not raise';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select count(*) from patients where id in ('b9000000-0000-0000-0000-000000000009', 'b0000000-0000-0000-0000-000000000000') and user_id is not null) = 0,
    'U8/U9: bound a row with empty or null phone';
end $$;

-- ===== no auth.uid() (signed in as authenticated with no sub): 42501 =====
set local role authenticated;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform claim_my_patient();
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
    perform claim_my_patient();
    raise exception 'anon could call claim_my_patient';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ===== hardening: unconfirmed phone and privileged accounts cannot claim =====
-- X1: phone not confirmed. X2: doctor, disabled by an admin. X3: caregiver (active). X4: admin (active).
-- Each has an unowned patient row with a matching phone.
reset role;
insert into auth.users (id, email, phone, phone_confirmed_at) values
  ('e1000000-0000-0000-0000-000000000001', 'x1@t', '66811110001', null),
  ('e2000000-0000-0000-0000-000000000002', 'x2@t', '66811110002', now()),
  ('e3000000-0000-0000-0000-000000000003', 'x3@t', '66811110003', now()),
  ('e4000000-0000-0000-0000-000000000004', 'x4@t', '66811110004', now());
insert into user_roles (user_id, role) values
  ('e2000000-0000-0000-0000-000000000002', 'doctor'),
  ('e3000000-0000-0000-0000-000000000003', 'caregiver'),
  ('e4000000-0000-0000-0000-000000000004', 'admin');
update profiles set is_active = true where id in ('e3000000-0000-0000-0000-000000000003', 'e4000000-0000-0000-0000-000000000004');
insert into patients (id, user_id, full_name, phone) values
  ('f1000000-0000-0000-0000-000000000001', null, 'X1 row', '0811110001'),
  ('f2000000-0000-0000-0000-000000000002', null, 'X2 row', '0811110002'),
  ('f3000000-0000-0000-0000-000000000003', null, 'X3 row', '0811110003'),
  ('f4000000-0000-0000-0000-000000000004', null, 'X4 row', '0811110004');
set local role authenticated;
do $$
declare u text;
begin
  foreach u in array array['e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002',
                           'e3000000-0000-0000-0000-000000000003', 'e4000000-0000-0000-0000-000000000004'] loop
    perform set_config('request.jwt.claims', '{"sub":"' || u || '"}', true);
    begin
      perform claim_my_patient();
      raise exception 'hardening: % could claim', u;
    exception when insufficient_privilege then null;
    end;
  end loop;
end $$;
reset role;
do $$
begin
  assert (select count(*) from patients where id::text like 'f_000000-%' and user_id is not null) = 0, 'hardening: a row was bound';
  assert not (select is_active from profiles where id = 'e1000000-0000-0000-0000-000000000001'), 'hardening: X1 activated';
  assert not (select is_active from profiles where id = 'e2000000-0000-0000-0000-000000000002'), 'hardening: disabled doctor re-enabled';
  assert not exists (select 1 from user_roles where user_id = 'e1000000-0000-0000-0000-000000000001'), 'hardening: X1 got a role';
  assert not exists (select 1 from audit_logs where actor::text like 'e_000000-%'), 'hardening: audit written';
end $$;

-- ===== guard still works for direct updates as `authenticated` =====
-- A patient has no UPDATE right on patients at all (RLS: 0 rows), so the real test of the guard is a doctor who
-- may edit the row (can_manage_plan) but is not admin: changing user_id must still raise 42501.
reset role;
insert into auth.users (id, email, phone, phone_confirmed_at) values ('dc000000-0000-0000-0000-00000000000c', 'doc@t', '66899999999', now());
update profiles set is_active = true where id = 'dc000000-0000-0000-0000-00000000000c';
insert into user_roles (user_id, role) values ('dc000000-0000-0000-0000-00000000000c', 'doctor');
insert into doctors (id, user_id, full_name) values ('dd000000-0000-0000-0000-00000000000d', 'dc000000-0000-0000-0000-00000000000c', 'Doc');
insert into patient_doctors (patient_id, doctor_id) values ('b2000000-0000-0000-0000-000000000002', 'dd000000-0000-0000-0000-00000000000d');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"dc000000-0000-0000-0000-00000000000c"}', true);
do $$
begin
  begin
    update patients set user_id = 'a4000000-0000-0000-0000-000000000004' where id = 'b2000000-0000-0000-0000-000000000002';
    raise exception 'guard: doctor re-pointed patients.user_id';
  exception when insufficient_privilege then null;
  end;
  -- positive control: the same doctor can edit a non-guarded column
  update patients set age = 40 where id = 'b2000000-0000-0000-0000-000000000002';
  assert (select age from patients where id = 'b2000000-0000-0000-0000-000000000002') = 40, 'guard: doctor could not edit age';
end $$;
-- doctors branch of the guard (rewritten with nested ifs): a doctor may not re-enable or re-point their own row
do $$
begin
  begin
    update doctors set is_active = not is_active where id = 'dd000000-0000-0000-0000-00000000000d';
    raise exception 'guard: doctor changed own is_active';
  exception when insufficient_privilege then null;
  end;
  update doctors set department = 'x' where id = 'dd000000-0000-0000-0000-00000000000d';
  assert (select department from doctors where id = 'dd000000-0000-0000-0000-00000000000d') = 'x', 'guard: doctor could not edit own department';
end $$;
-- the claimed patient editing their own user_id directly: blocked (RLS or guard), row unchanged
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
begin
  begin
    update patients set user_id = 'a4000000-0000-0000-0000-000000000004' where id = 'b2000000-0000-0000-0000-000000000002';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select user_id from patients where id = 'b2000000-0000-0000-0000-000000000002') = 'a2000000-0000-0000-0000-000000000002', 'guard: user_id changed';
end $$;

rollback;
