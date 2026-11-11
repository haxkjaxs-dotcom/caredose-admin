-- integration.sql section 13:
--  * a non-admin may not move a medication log to another plan / schedule / time over REST (log_u only checked recorded_by,
--    so a patient could re-point a log at another patient's plan, or push scheduled_at forward to keep the 24h edit window open)
--  * only Admin or an assigned doctor edits the patient record; a caregiver with can_manage_plan manages plans, not the chart
-- Users: AD admin, DA doctor of P1, CY caregiver of P1 (can_manage_plan), PU patient P1. Plan1/S1 + S1x (P1), plan2/S2 (P2).
begin;

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'ad@t'), ('a2000000-0000-0000-0000-000000000002', 'da@t'),
  ('a3000000-0000-0000-0000-000000000003', 'cy@t'), ('a5000000-0000-0000-0000-000000000005', 'pu@t');
update profiles set is_active = true;
insert into user_roles (user_id, role) values
  ('a1000000-0000-0000-0000-000000000001', 'admin'), ('a2000000-0000-0000-0000-000000000002', 'doctor'),
  ('a3000000-0000-0000-0000-000000000003', 'caregiver'), ('a5000000-0000-0000-0000-000000000005', 'patient');
insert into patients (id, user_id, full_name, drug_allergies) values
  ('b1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005', 'P1', 'penicillin'),
  ('b2000000-0000-0000-0000-000000000002', null, 'P2', null);
insert into doctors (id, user_id, full_name) values ('d1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'DA');
insert into patient_doctors (patient_id, doctor_id) values ('b1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001');
insert into caregivers (id, user_id, full_name) values ('c1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'CY');
insert into patient_caregivers (patient_id, caregiver_id, status, can_manage_plan) values
  ('b1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'confirmed', true);
insert into medicines (id, generic_name) values ('e1000000-0000-0000-0000-000000000001', 'M1');
insert into medication_plans (id, patient_id, medicine_id, dose, start_date) values
  ('f1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'D1', current_date),
  ('f2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'D2', current_date);
insert into medication_schedules (id, plan_id, time_of_day) values
  ('51000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '08:00'),
  ('51100000-0000-0000-0000-000000000011', 'f1000000-0000-0000-0000-000000000001', '20:00'),
  ('52000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', '08:00');
insert into medication_logs (id, plan_id, schedule_id, scheduled_at) values
  ('11000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', date_trunc('minute', now()) - interval '1 hour');

-- ===== 1) medication logs: patient and caregiver record a dose, but cannot move the log =====
do $$
declare u text; n int;
begin
  foreach u in array array['a5000000-0000-0000-0000-000000000005', 'a3000000-0000-0000-0000-000000000003'] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"' || u || '"}', true);
    -- positive control: recording the dose still works
    update medication_logs set status = 'taken', taken_at = now(), recorded_by = u::uuid where id = '11000000-0000-0000-0000-000000000001';
    get diagnostics n = row_count;
    assert n = 1, u || ' could not record a dose';
    -- re-point at another patient's plan
    begin
      update medication_logs set plan_id = 'f2000000-0000-0000-0000-000000000002', schedule_id = '52000000-0000-0000-0000-000000000002',
             recorded_by = u::uuid where id = '11000000-0000-0000-0000-000000000001';
      raise exception '% moved a log to another patient''s plan', u;
    exception when insufficient_privilege then null;
    end;
    -- re-point at another schedule of the same plan
    begin
      update medication_logs set schedule_id = '51100000-0000-0000-0000-000000000011', recorded_by = u::uuid
       where id = '11000000-0000-0000-0000-000000000001';
      raise exception '% moved a log to another schedule', u;
    exception when insufficient_privilege then null;
    end;
    -- push the scheduled time forward (would keep the 24h edit window open for ever)
    begin
      update medication_logs set scheduled_at = now() + interval '30 days', recorded_by = u::uuid
       where id = '11000000-0000-0000-0000-000000000001';
      raise exception '% moved scheduled_at', u;
    exception when insufficient_privilege then null;
    end;
    reset role;
  end loop;
end $$;

-- the app's offline sync upsert (same schedule + time, all columns re-sent) still updates the row
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-0000-0000-000000000005"}', true);
insert into medication_logs (plan_id, schedule_id, scheduled_at, status, recorded_by, note)
  select plan_id, schedule_id, scheduled_at, 'taken', 'a5000000-0000-0000-0000-000000000005', 'synced'
    from medication_logs where id = '11000000-0000-0000-0000-000000000001'
  on conflict (schedule_id, scheduled_at) do update
    set plan_id = excluded.plan_id, status = excluded.status, recorded_by = excluded.recorded_by, note = excluded.note;
reset role;
do $$
begin
  assert (select note from medication_logs where id = '11000000-0000-0000-0000-000000000001') = 'synced', 'sync upsert did not update';
  assert (select plan_id from medication_logs where id = '11000000-0000-0000-0000-000000000001') = 'f1000000-0000-0000-0000-000000000001', 'log left its plan';
end $$;

-- admin may still correct the time
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001"}', true);
update medication_logs set scheduled_at = scheduled_at - interval '5 minutes', recorded_by = 'a1000000-0000-0000-0000-000000000001'
 where id = '11000000-0000-0000-0000-000000000001';
reset role;
do $$
begin
  assert (select scheduled_at from medication_logs where id = '11000000-0000-0000-0000-000000000001')
         = date_trunc('minute', now()) - interval '65 minutes', 'admin could not correct scheduled_at';
end $$;

-- ===== 2) patient record: caregiver with can_manage_plan is read-only, the assigned doctor edits =====
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000003"}', true);
do $$
declare n int;
begin
  assert (select count(*) from patients where id = 'b1000000-0000-0000-0000-000000000001') = 1, 'caregiver lost read access';
  update patients set drug_allergies = null, phone = '0899999999' where id = 'b1000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'caregiver edited the patient record';
  -- plan management itself is unchanged
  perform save_plan(null, 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '1 tab', null,
                    current_date, null, null, array['09:00'], 'active');
end $$;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002"}', true);
do $$
declare n int;
begin
  update patients set conditions = 'HT' where id = 'b1000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'assigned doctor could not edit the patient';
  -- a doctor not assigned to P2 still cannot
  update patients set conditions = 'HT' where id = 'b2000000-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'doctor edited a patient not assigned to them';
end $$;
reset role;
do $$
begin
  assert (select drug_allergies from patients where id = 'b1000000-0000-0000-0000-000000000001') = 'penicillin', 'allergy was wiped';
end $$;

rollback;
