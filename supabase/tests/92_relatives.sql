-- list_my_relatives / save_my_relative / delete_my_relative (integration.sql #18).
-- Users: AD admin, DO doctor, CG caregiver with an account, PU patient of P1, PW patient of P3, PX disabled patient of P4.
-- Caregivers: CGR = CG's account row (phone 0899990001); KIN = contact an admin made for P1; OLD = KIN-like row whose link is revoked.
begin;

insert into auth.users (id, email) values
  ('e1000000-0000-0000-0000-0000000000e1', 'ad4@t'),
  ('e2000000-0000-0000-0000-0000000000e2', 'do4@t'),
  ('e3000000-0000-0000-0000-0000000000e3', 'cg4@t'),
  ('e4000000-0000-0000-0000-0000000000e4', 'pu4@t'),
  ('e5000000-0000-0000-0000-0000000000e5', 'pw4@t'),
  ('e6000000-0000-0000-0000-0000000000e6', 'px4@t');
update profiles set is_active = true where id <> 'e6000000-0000-0000-0000-0000000000e6';
update profiles set is_active = false where id = 'e6000000-0000-0000-0000-0000000000e6';
insert into user_roles (user_id, role) values
  ('e1000000-0000-0000-0000-0000000000e1', 'admin'),
  ('e2000000-0000-0000-0000-0000000000e2', 'doctor'),
  ('e3000000-0000-0000-0000-0000000000e3', 'caregiver'),
  ('e4000000-0000-0000-0000-0000000000e4', 'patient'),
  ('e5000000-0000-0000-0000-0000000000e5', 'patient'),
  ('e6000000-0000-0000-0000-0000000000e6', 'patient');
insert into patients (id, user_id, full_name) values
  ('f1000000-0000-0000-0000-0000000000f1', 'e4000000-0000-0000-0000-0000000000e4', 'P1'),
  ('f3000000-0000-0000-0000-0000000000f3', 'e5000000-0000-0000-0000-0000000000e5', 'P3'),
  ('f4000000-0000-0000-0000-0000000000f4', 'e6000000-0000-0000-0000-0000000000e6', 'P4');
insert into caregivers (id, user_id, full_name, phone) values
  ('d1000000-0000-0000-0000-0000000000d1', 'e3000000-0000-0000-0000-0000000000e3', 'CGR', '0899990001'),
  ('d2000000-0000-0000-0000-0000000000d2', null, 'KIN', '0888880002'),
  ('d3000000-0000-0000-0000-0000000000d3', null, 'OLD', '0888880003');
insert into patient_caregivers (patient_id, caregiver_id, relationship, status, revoked_at) values
  ('f1000000-0000-0000-0000-0000000000f1', 'd2000000-0000-0000-0000-0000000000d2', 'พี่', 'pending', null),
  ('f1000000-0000-0000-0000-0000000000f1', 'd3000000-0000-0000-0000-0000000000d3', 'เก่า', 'revoked', now());

-- ===== PU creates a relative: trimmed, contact-only, never merged with the account that has the same phone =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare rid uuid;
begin
  rid := save_my_relative(null, '  ก  ', ' ลูก ', ' 0899990001 ');
  assert rid is not null, 'create: no id';
  perform set_config('t.r1', rid::text, true);
end $$;
reset role;
do $$
declare r uuid := current_setting('t.r1')::uuid;
begin
  assert (select count(*) from caregivers where id = r and user_id is null and added_by_patient
            and full_name = 'ก' and phone = '0899990001') = 1, 'create: caregivers row wrong';
  assert (select count(*) from patient_caregivers where caregiver_id = r and patient_id = 'f1000000-0000-0000-0000-0000000000f1'
            and relationship = 'ลูก' and status = 'confirmed' and revoked_at is null
            and not can_manage_plan and not can_manage_appt) = 1, 'create: link wrong';
  assert r <> 'd1000000-0000-0000-0000-0000000000d1', 'create: reused the account row of the same phone';
  assert (select count(*) from caregivers where phone = '0899990001') = 2, 'create: expected a new row next to the account row';
  assert not exists (select 1 from patient_caregivers where caregiver_id = 'd1000000-0000-0000-0000-0000000000d1'), 'create: the account got linked';
  assert (select count(*) from audit_logs where action = 'save_relative' and actor = 'e4000000-0000-0000-0000-0000000000e4') = 1, 'create: audit row missing';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e3000000-0000-0000-0000-0000000000e3"}', true);
do $$ begin
  assert not can_see_patient('f1000000-0000-0000-0000-0000000000f1'), 'the caregiver account with the same phone must not see P1';
end $$;
reset role;

-- ===== list: own patient only; revoked links hidden; editable only for the patient's own contacts =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare r uuid := current_setting('t.r1')::uuid;
begin
  assert (select count(*) from list_my_relatives()) = 2, 'list: PU should see its own contact and the admin one, not the revoked one';
  assert (select editable from list_my_relatives() where id = r), 'list: own contact must be editable';
  assert not (select editable from list_my_relatives() where id = 'd2000000-0000-0000-0000-0000000000d2'), 'list: admin contact must not be editable';
  assert (select name || '|' || relationship || '|' || phone from list_my_relatives() where id = r) = 'ก|ลูก|0899990001', 'list: fields wrong';
end $$;
select set_config('request.jwt.claims', '{"sub":"e5000000-0000-0000-0000-0000000000e5"}', true);
do $$ begin
  assert (select count(*) from list_my_relatives()) = 0, 'list: PW must not see P1 contacts';
end $$;
reset role;

-- ===== edit: own contact yes; admin contact and other patients no =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare r uuid := current_setting('t.r1')::uuid;
begin
  assert save_my_relative(r, 'ข', 'แม่', '0811112222') = r, 'edit: id changed';
  begin
    perform save_my_relative('d2000000-0000-0000-0000-0000000000d2', 'x', 'y', '1');
    raise exception 'edited an admin contact';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"e5000000-0000-0000-0000-0000000000e5"}', true);
do $$
begin
  begin
    perform save_my_relative(current_setting('t.r1')::uuid, 'x', 'y', '1');
    raise exception 'edited another patient''s contact';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
declare r uuid := current_setting('t.r1')::uuid;
begin
  assert (select full_name || '|' || phone from caregivers where id = r) = 'ข|0811112222', 'edit: caregivers row not updated';
  assert (select relationship from patient_caregivers where caregiver_id = r) = 'แม่', 'edit: relationship not updated';
  assert (select full_name from caregivers where id = 'd2000000-0000-0000-0000-0000000000d2') = 'KIN', 'edit: admin contact changed';
end $$;

-- ===== a contact an admin also linked to another patient is no longer the patient's to change =====
insert into patient_caregivers (patient_id, caregiver_id, status)
  values ('f3000000-0000-0000-0000-0000000000f3', current_setting('t.r1')::uuid, 'confirmed');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare r uuid := current_setting('t.r1')::uuid;
begin
  assert not (select editable from list_my_relatives() where id = r), 'shared: must not be editable';
  begin perform save_my_relative(r, 'x', 'y', '1'); raise exception 'shared contact edited';
  exception when insufficient_privilege then null; end;
  begin perform delete_my_relative(r); raise exception 'shared contact deleted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from patient_caregivers where patient_id = 'f3000000-0000-0000-0000-0000000000f3';

-- ===== delete: own contact goes with its link; the admin's contact is refused =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
begin
  begin perform delete_my_relative('d2000000-0000-0000-0000-0000000000d2'); raise exception 'deleted an admin contact';
  exception when insufficient_privilege then null; end;
  perform delete_my_relative(current_setting('t.r1')::uuid);
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from caregivers where id = current_setting('t.r1')::uuid), 'delete: caregivers row left behind';
  assert not exists (select 1 from patient_caregivers where caregiver_id = current_setting('t.r1')::uuid), 'delete: link left behind';
  assert exists (select 1 from caregivers where id = 'd2000000-0000-0000-0000-0000000000d2'), 'delete: admin contact vanished';
end $$;

-- ===== validation: 22023, nothing written; limits are inclusive =====
select set_config('t.n_cg', (select count(*) from caregivers)::text, true);
select set_config('t.n_pc', (select count(*) from patient_caregivers)::text, true);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare
  bad text[][] := array[
    array['', 'ลูก', '1'], array['   ', 'ลูก', '1'], array[repeat('ก', 101), 'ลูก', '1'],
    array['ก', repeat('ก', 51), '1'], array['ก', 'ลูก', ''], array['ก', 'ลูก', '   '], array['ก', 'ลูก', repeat('1', 21)]
  ];
  c text[];
begin
  foreach c slice 1 in array bad loop
    begin
      perform save_my_relative(null, c[1], c[2], c[3]);
      raise exception 'invalid input accepted: [%] [%] [%]', left(c[1], 5), left(c[2], 5), left(c[3], 5);
    exception when sqlstate '22023' then null;
    end;
  end loop;
end $$;
reset role;
do $$
begin
  assert (select count(*) from caregivers) = current_setting('t.n_cg')::int, 'validation: rejected calls wrote caregivers';
  assert (select count(*) from patient_caregivers) = current_setting('t.n_pc')::int, 'validation: rejected calls wrote links';
end $$;
-- boundaries on PW (no contacts yet); an empty relationship is allowed and stored as null
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5000000-0000-0000-0000-0000000000e5"}', true);
do $$
declare rid uuid;
begin
  perform save_my_relative(null, repeat('ก', 100), repeat('ข', 50), repeat('1', 20));
  rid := save_my_relative(null, 'ไม่ระบุ', '  ', '0812345678');
  perform set_config('t.empty_rel', rid::text, true);
end $$;
reset role;
do $$
begin
  assert (select relationship from patient_caregivers where caregiver_id = current_setting('t.empty_rel')::uuid) is null, 'empty relationship must be stored as null';
end $$;

-- ===== the limit: 20 live links per patient (revoked ones do not count); the 21st is refused =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-0000000000e4"}', true);
do $$
declare have int; i int;
begin
  select count(*) into have from list_my_relatives();
  for i in 1..(20 - have) loop
    perform save_my_relative(null, 'N' || i, 'x', '08' || i);
  end loop;
  assert (select count(*) from list_my_relatives()) = 20, 'limit: should be exactly 20';
  begin
    perform save_my_relative(null, 'N21', 'x', '1');
    raise exception 'the 21st relative was accepted';
  exception when sqlstate '22023' then null;
  end;
end $$;
reset role;

-- ===== who may call: only a patient with an active account =====
do $$
declare u text; n int := (select count(*) from caregivers);
begin
  foreach u in array array['e1000000-0000-0000-0000-0000000000e1', 'e2000000-0000-0000-0000-0000000000e2',
                           'e3000000-0000-0000-0000-0000000000e3', 'e6000000-0000-0000-0000-0000000000e6', ''] loop
    perform set_config('request.jwt.claims', case when u = '' then '{}' else json_build_object('sub', u)::text end, true);
    set local role authenticated;
    begin perform list_my_relatives(); raise exception 'list allowed for %', u;
    exception when insufficient_privilege then null; end;
    begin perform save_my_relative(null, 'x', 'y', '1'); raise exception 'save allowed for %', u;
    exception when insufficient_privilege then null; end;
    begin perform delete_my_relative('d2000000-0000-0000-0000-0000000000d2'); raise exception 'delete allowed for %', u;
    exception when insufficient_privilege then null; end;
    reset role;
  end loop;
  assert (select count(*) from caregivers) = n, 'refused calls wrote rows';
end $$;

rollback;
