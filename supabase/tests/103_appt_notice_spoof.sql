-- integration.sql section 24 hardening: the appointment notice is an admin_message, so only staff (admin / doctor) or the server may
-- cause one. A relative who manages the plan (appt_i) could otherwise push any text to the patient as a hospital message.
-- The body is capped at 500 characters like send_notification.
-- Users: DA doctor, CY caregiver of P1 with can_manage_plan, PU patient P1.
begin;
insert into auth.users (id, email) values
  ('a1031000-0000-0000-0000-000000000001', 'da@t'), ('a1032000-0000-0000-0000-000000000002', 'cy@t'),
  ('a1033000-0000-0000-0000-000000000003', 'pu@t');
update profiles set is_active = true where id::text like 'a103_000%';
insert into user_roles (user_id, role) values
  ('a1031000-0000-0000-0000-000000000001', 'doctor'), ('a1032000-0000-0000-0000-000000000002', 'caregiver'),
  ('a1033000-0000-0000-0000-000000000003', 'patient');
insert into patients (id, user_id, full_name) values ('b1031000-0000-0000-0000-000000000001', 'a1033000-0000-0000-0000-000000000003', 'P1');
insert into caregivers (id, user_id, full_name) values ('c1032000-0000-0000-0000-000000000002', 'a1032000-0000-0000-0000-000000000002', 'CY');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('b1031000-0000-0000-0000-000000000001', 'c1032000-0000-0000-0000-000000000002', 'confirmed', true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1032000-0000-0000-0000-000000000002"}', true);
insert into appointments (patient_id, appointment_at, place, reason)
  values ('b1031000-0000-0000-0000-000000000001', now() + interval '1 day', 'โทรด่วน 0900000000', 'โอนเงินค่ายา');
select set_config('request.jwt.claims', '{"sub":"a1031000-0000-0000-0000-000000000001"}', true);
insert into appointments (patient_id, appointment_at, place, reason)
  values ('b1031000-0000-0000-0000-000000000001', now() + interval '2 days', 'OPD', repeat('ก', 900));
reset role;
do $$
begin
  assert not exists (select 1 from notifications where body like '%โทรด่วน%'), 'a relative sent an admin_message';
  assert (select count(*) from notifications where user_id = 'a1033000-0000-0000-0000-000000000003') = 1, 'doctor appointment did not notify';
  assert (select char_length(body) from notifications where user_id = 'a1033000-0000-0000-0000-000000000003') <= 500, 'body not capped';
end $$;
rollback;
