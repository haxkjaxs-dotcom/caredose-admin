-- Security fixes on top of schema.sql. Run after schema.sql (already applied to eokqjjodfgdpgzievgln on 2026-11-03).
-- Safe to re-run: every policy is dropped before it is recreated.

-- 1) A disabled account loses every role-based right immediately, not only patient visibility.
create or replace function has_role(r app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles ur join profiles p on p.id = ur.user_id
                 where ur.user_id = auth.uid() and ur.role = r and p.is_active)
$$;

-- 2) Accounts made outside the create-user function (e.g. public sign-up) start disabled.
alter table profiles alter column is_active set default false;

-- 3) Only Admin may change who a record belongs to or re-enable a doctor.
--    auth.uid() is null in the SQL editor / service role, so server-side maintenance still works.
create or replace function guard_admin_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not has_role('admin') then
    if tg_table_name = 'doctors' and (new.user_id is distinct from old.user_id or new.is_active is distinct from old.is_active) then
      raise exception 'เฉพาะ Admin เท่านั้นที่แก้ไขข้อมูลนี้ได้' using errcode = '42501';
    end if;
    if tg_table_name = 'patients' and new.user_id is distinct from old.user_id then
      raise exception 'เฉพาะ Admin เท่านั้นที่แก้ไขข้อมูลนี้ได้' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;
drop trigger if exists doctors_guard on doctors;
create trigger doctors_guard before update on doctors for each row execute function guard_admin_columns();
drop trigger if exists patients_guard on patients;
create trigger patients_guard before update on patients for each row execute function guard_admin_columns();

-- 4) Doctors table: only Admin creates/deletes. A doctor may edit only their own row.
--    (Before: any signed-in user could insert a doctors row for themselves.)
drop policy if exists doctors_w on doctors;
drop policy if exists doctors_u_self on doctors;
create policy doctors_w on doctors for all to authenticated using (has_role('admin')) with check (has_role('admin'));
create policy doctors_u_self on doctors for update to authenticated
  using (user_id = auth.uid() and has_role('doctor')) with check (user_id = auth.uid() and has_role('doctor'));

-- 5) Caregivers: a doctor sees only caregivers of patients they can see (before: every caregiver's phone).
drop policy if exists cg_r on caregivers;
create policy cg_r on caregivers for select to authenticated using (
  user_id = auth.uid() or has_role('admin')
  or exists (select 1 from patient_caregivers pc where pc.caregiver_id = caregivers.id and can_see_patient(pc.patient_id))
);

-- 6) A patient may only revoke a caregiver link, not grant itself extra rights.
drop policy if exists pc_revoke on patient_caregivers;
create policy pc_revoke on patient_caregivers for update to authenticated
  using (exists (select 1 from patients p where p.id = patient_id and p.user_id = auth.uid()))
  with check (status = 'revoked' and exists (select 1 from patients p where p.id = patient_id and p.user_id = auth.uid()));

-- 7) Medication logs: doctors stay read-only, and the recorder is always the caller (no spoofing).
drop policy if exists log_i on medication_logs;
drop policy if exists log_u on medication_logs;
create policy log_i on medication_logs for insert to authenticated with check (
  recorded_by = auth.uid()
  and (has_role('admin') or not has_role('doctor'))
  and exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id))
);
create policy log_u on medication_logs for update to authenticated
  using (
    exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id))
    and (has_role('admin') or (not has_role('doctor') and now() < scheduled_at + interval '24 hours'))
  )
  with check (recorded_by = auth.uid() or has_role('admin'));

-- 8) Audit log: from the browser only Admin may write, as themselves. Functions write as definer.
drop policy if exists audit_i on audit_logs;
create policy audit_i on audit_logs for insert to authenticated with check (actor = auth.uid() and has_role('admin'));

-- 9) Follow-up notes: the author is the caller.
drop policy if exists fu_i on follow_ups;
create policy fu_i on follow_ups for insert to authenticated with check (can_manage_plan(patient_id) and created_by = auth.uid());

-- 10) Consents: nobody can record consent on someone else's behalf (before: any user, by setting given_by).
drop policy if exists consents_i on consents;
create policy consents_i on consents for insert to authenticated
  with check (given_by = auth.uid() and (user_id = auth.uid() or has_role('admin')));
