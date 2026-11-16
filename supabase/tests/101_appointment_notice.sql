-- integration.sql section 24: appointments notify the patient's app. P1 has a login (U1), P2 has none.
begin;
insert into auth.users (id, email) values ('a1101000-0000-0000-0000-000000000001', 'an@t');
insert into patients (id, user_id, full_name) values
  ('b1101000-0000-0000-0000-000000000001', 'a1101000-0000-0000-0000-000000000001', 'P1'),
  ('b2101000-0000-0000-0000-000000000002', null, 'P2');
do $$
declare n int;
begin
  insert into appointments (id, patient_id, appointment_at, place, reason)
    values ('d1101000-0000-0000-0000-000000000001', 'b1101000-0000-0000-0000-000000000001', '2026-12-01 02:30+00', 'โรงพยาบาล', 'ตรวจความดัน');
  assert (select count(*) from notifications where user_id = 'a1101000-0000-0000-0000-000000000001' and title = 'นัดหมายใหม่'
            and body = '01/12/2026 09:30 น. ที่ โรงพยาบาล (ตรวจความดัน)') = 1, 'new appointment did not notify the patient';
  update appointments set status = 'done' where id = 'd1101000-0000-0000-0000-000000000001';
  update appointments set status = 'pending' where id = 'd1101000-0000-0000-0000-000000000001';
  update appointments set status = 'postponed' where id = 'd1101000-0000-0000-0000-000000000001';
  update appointments set place = 'คลินิก' where id = 'd1101000-0000-0000-0000-000000000001';
  update appointments set status = 'cancelled' where id = 'd1101000-0000-0000-0000-000000000001';
  assert (select count(*) from notifications where user_id = 'a1101000-0000-0000-0000-000000000001') = 4, 'expected new + postponed + changed + cancelled only';
  insert into appointments (patient_id, appointment_at) values ('b2101000-0000-0000-0000-000000000002', now());
  select count(*) into n from notifications where patient_id = 'b2101000-0000-0000-0000-000000000002';
  assert n = 0, 'a patient with no login got a notification';
end $$;
rollback;
