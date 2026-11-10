-- send_notification (integration.sql, phase 2).
-- Users: AD admin, DA disabled admin, DO doctor, CG caregiver, PU patient user of P1, PW patient user of P3.
-- Patients: P1 linked to PU, P2 not linked, P3 linked to PW.
begin;

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-0000000000a1', 'ad3@t'),
  ('a2000000-0000-0000-0000-0000000000a2', 'da3@t'),
  ('a3000000-0000-0000-0000-0000000000a3', 'do3@t'),
  ('a4000000-0000-0000-0000-0000000000a4', 'cg3@t'),
  ('a5000000-0000-0000-0000-0000000000a5', 'pu3@t'),
  ('a6000000-0000-0000-0000-0000000000a6', 'pw3@t');
update profiles set is_active = true where id <> 'a2000000-0000-0000-0000-0000000000a2';
insert into user_roles (user_id, role) values
  ('a1000000-0000-0000-0000-0000000000a1', 'admin'),
  ('a2000000-0000-0000-0000-0000000000a2', 'admin'),
  ('a3000000-0000-0000-0000-0000000000a3', 'doctor'),
  ('a4000000-0000-0000-0000-0000000000a4', 'caregiver'),
  ('a5000000-0000-0000-0000-0000000000a5', 'patient'),
  ('a6000000-0000-0000-0000-0000000000a6', 'patient');
insert into patients (id, user_id, full_name) values
  ('c1000000-0000-0000-0000-0000000000c1', 'a5000000-0000-0000-0000-0000000000a5', 'N1'),
  ('c2000000-0000-0000-0000-0000000000c2', null, 'N2'),
  ('c3000000-0000-0000-0000-0000000000c3', 'a6000000-0000-0000-0000-0000000000a6', 'N3');

-- ===== admin sends: trimmed, targeted at the patient's login, audited =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-0000000000a1"}', true);
do $$
declare nid uuid;
begin
  nid := send_notification('c1000000-0000-0000-0000-0000000000c1', '  หัวข้อ  ', ' ข้อความ ');
  assert nid is not null, 'send: no id returned';
  perform set_config('t.nid', nid::text, true);
end $$;
reset role;
do $$
begin
  assert (select count(*) from notifications where id = current_setting('t.nid')::uuid
            and user_id = 'a5000000-0000-0000-0000-0000000000a5' and type = 'admin_message'
            and title = 'หัวข้อ' and body = 'ข้อความ' and read = false
            and patient_id = 'c1000000-0000-0000-0000-0000000000c1') = 1, 'send: notifications row wrong';
  assert (select count(*) from audit_logs where action = 'send_notification'
            and actor = 'a1000000-0000-0000-0000-0000000000a1') = 1, 'send: audit row missing';
end $$;

-- ===== isolation: PU sees it, PW does not =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-0000-0000-0000000000a5"}', true);
do $$ begin
  assert (select count(*) from notifications) = 1, 'PU should see exactly its own notice';
end $$;
select set_config('request.jwt.claims', '{"sub":"a6000000-0000-0000-0000-0000000000a6"}', true);
do $$ begin
  assert (select count(*) from notifications) = 0, 'PW must not see PU''s notice';
end $$;
reset role;

-- ===== who may call: everyone but an active admin gets 42501 =====
select set_config('t.n_notif', (select count(*) from notifications)::text, true);
do $$
declare u text;
begin
  foreach u in array array['a2000000-0000-0000-0000-0000000000a2', 'a3000000-0000-0000-0000-0000000000a3',
                           'a4000000-0000-0000-0000-0000000000a4', 'a5000000-0000-0000-0000-0000000000a5'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', u)::text, true);
    set local role authenticated;
    begin
      perform send_notification('c1000000-0000-0000-0000-0000000000c1', 't', 'b');
      raise exception 'user % was allowed to send', u;
    exception when insufficient_privilege then null;
    end;
    reset role;
  end loop;
  assert (select count(*) from notifications) = current_setting('t.n_notif')::int, 'refused calls wrote rows';
end $$;

-- ===== validation: nothing written =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-0000000000a1"}', true);
do $$
declare
  p1 constant uuid := 'c1000000-0000-0000-0000-0000000000c1';
  bad text[][];
  c text[];
begin
  -- unlinked patient and unknown patient
  begin
    perform send_notification('c2000000-0000-0000-0000-0000000000c2', 't', 'b');
    raise exception 'unlinked patient accepted';
  exception when sqlstate '22023' then
    assert sqlstate is not null;
  end;
  begin
    perform send_notification('c9000000-0000-0000-0000-0000000000c9', 't', 'b');
    raise exception 'unknown patient accepted';
  exception when sqlstate '22023' then null;
  end;
  bad := array[
    array['', 'b'], array['   ', 'b'], array[repeat('ก', 101), 'b'],
    array['t', ''], array['t', E' \n '], array['t', repeat('ก', 501)]
  ];
  foreach c slice 1 in array bad loop
    begin
      perform send_notification(p1, c[1], c[2]);
      raise exception 'invalid input accepted: [%] [%]', left(c[1], 10), left(c[2], 10);
    exception when sqlstate '22023' then null;
    end;
  end loop;
  -- boundaries: 100 Thai characters of title and 500 of body are fine
  perform send_notification(p1, repeat('ก', 100), repeat('ข', 500));
end $$;
reset role;
-- an admin cannot read other users' notices, so count as the owner: only the boundary call wrote a row
do $$ begin
  assert (select count(*) from notifications) = current_setting('t.n_notif')::int + 1, 'invalid calls wrote rows or boundary lengths rejected';
end $$;

rollback;
