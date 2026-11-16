-- integration.sql section 27: send_test_notification is Admin only and reaches active patient / caregiver accounts only.
begin;
insert into auth.users (id, email) values
  ('a1110000-0000-0000-0000-000000000001', 'ad@t'), ('a2110000-0000-0000-0000-000000000002', 'dr@t'),
  ('a3110000-0000-0000-0000-000000000003', 'pa@t'), ('a4110000-0000-0000-0000-000000000004', 'cg@t'),
  ('a5110000-0000-0000-0000-000000000005', 'off@t');
update profiles set is_active = true where id::text like 'a_110000%' and id::text <> 'a5110000-0000-0000-0000-000000000005';
insert into user_roles (user_id, role) values
  ('a1110000-0000-0000-0000-000000000001', 'admin'), ('a2110000-0000-0000-0000-000000000002', 'doctor'),
  ('a3110000-0000-0000-0000-000000000003', 'patient'), ('a4110000-0000-0000-0000-000000000004', 'caregiver'),
  ('a5110000-0000-0000-0000-000000000005', 'patient');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2110000-0000-0000-0000-000000000002"}', true);
do $$
begin
  begin perform send_test_notification('now'); raise exception 'doctor sent a test notification'; exception when sqlstate '42501' then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"a1110000-0000-0000-0000-000000000001"}', true);
do $$
begin
  begin perform send_test_notification('bogus'); raise exception 'bad kind accepted'; exception when sqlstate '22023' then null; end;
  assert send_test_notification('before') = 2, 'expected the active patient and caregiver only';
end $$;
reset role;
do $$
begin
  assert (select count(*) from notifications where title = '[ทดสอบ] ใกล้ถึงเวลาทานยา'
            and user_id in ('a3110000-0000-0000-0000-000000000003', 'a4110000-0000-0000-0000-000000000004')) = 2, 'recipients missing';
  assert not exists (select 1 from notifications where user_id in ('a1110000-0000-0000-0000-000000000001', 'a2110000-0000-0000-0000-000000000002', 'a5110000-0000-0000-0000-000000000005')), 'staff or disabled account got one';
end $$;
rollback;
