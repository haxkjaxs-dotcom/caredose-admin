-- CareDose schema for the web back office (Supabase project eokqjjodfgdpgzievgln).
-- Run once: Dashboard > SQL Editor > paste this whole file > Run.
-- Rebuilt from the table/policy listing of the old project (wtmboyoidxgqyfstbkau).
-- Function bodies of the old project were not readable, so has_role, can_see_patient
-- and can_manage_plan below are a reconstruction. Check them before real patient data goes in.

-- ---------- types ----------
create type app_role as enum ('patient', 'caregiver', 'doctor', 'admin');
-- "late" is not a status: it is the is_late flag on a taken log.
create type log_status as enum ('pending', 'taken', 'skipped', 'missed');

-- ---------- tables ----------
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  phone text,
  is_active boolean not null default true,
  must_change_pin boolean not null default true,
  user_no bigint generated always as identity
);

create table user_roles (
  user_id uuid not null references auth.users on delete cascade,
  role app_role not null,
  primary key (user_id, role)
);

create table patients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  full_name text not null,
  age integer,
  gender text,
  conditions text,
  drug_allergies text,
  phone text
);

create table doctors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  full_name text not null,
  department text,
  specialty text,
  phone text,
  is_active boolean not null default true
);

create table caregivers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  full_name text not null,
  phone text
);

create table patient_doctors (
  patient_id uuid not null references patients on delete cascade,
  doctor_id uuid not null references doctors on delete cascade,
  is_primary boolean not null default false,
  active boolean not null default true,
  primary key (patient_id, doctor_id)
);

create table patient_caregivers (
  patient_id uuid not null references patients on delete cascade,
  caregiver_id uuid not null references caregivers on delete cascade,
  relationship text,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'revoked')),
  can_manage_plan boolean not null default false,
  can_manage_appt boolean not null default false,
  confirmed_at timestamptz,
  revoked_at timestamptz,
  primary key (patient_id, caregiver_id)
);

create table medicines (
  id uuid primary key default gen_random_uuid(),
  generic_name text not null,
  trade_name text,
  form text,
  strength text,
  unit text,
  usage text,
  warning text,
  stock integer not null default 0,
  image_path text,
  is_active boolean not null default true
);

create table medication_plans (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients on delete cascade,
  medicine_id uuid not null references medicines,
  dose text not null,
  quantity numeric,
  meal_relation text,
  start_date date not null,
  end_date date,
  status text not null default 'active' check (status in ('active', 'stopped')),
  doctor_note text,
  created_by uuid references auth.users on delete set null
);

create table medication_schedules (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references medication_plans on delete cascade,
  time_of_day time not null,
  days_of_week integer[],
  interval_days integer
);

create table medication_logs (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references medication_plans on delete cascade,
  schedule_id uuid not null references medication_schedules on delete cascade,
  scheduled_at timestamptz not null,
  status log_status not null default 'pending',
  taken_at timestamptz,
  received_at timestamptz not null default now(),
  is_late boolean not null default false,
  recorded_by uuid references auth.users on delete set null,
  note text,
  notified boolean not null default false,
  unique (schedule_id, scheduled_at)
);

create table appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients on delete cascade,
  doctor_id uuid references doctors on delete set null,
  appointment_at timestamptz not null,
  place text,
  department text,
  reason text,
  note text,
  status text not null default 'pending' check (status in ('pending', 'scheduled', 'done', 'postponed', 'cancelled'))
);

create table audit_logs (
  id bigint generated always as identity primary key,
  actor uuid,
  action text not null,
  table_name text,
  row_id text,
  old_value jsonb,
  new_value jsonb,
  reason text,
  at timestamptz not null default now()
);

create table bmi_logs (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients on delete cascade,
  weight_kg numeric not null,
  height_cm numeric not null,
  bmi_value numeric not null,
  category text not null,
  calculated_at timestamptz not null default now()
);

create table follow_ups (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients on delete cascade,
  note text not null,
  by_name text not null,
  created_by uuid references auth.users on delete set null,
  at timestamptz not null default now()
);

create table consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  version text not null,
  given_by uuid references auth.users on delete set null,
  given_at timestamptz not null default now(),
  withdrawn_at timestamptz
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  type text not null,
  title text not null,
  body text,
  patient_id uuid references patients on delete cascade,
  dedupe_key text unique,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  device_id text not null,
  platform text not null,
  token text,
  notification_permission boolean,
  last_seen timestamptz not null default now(),
  unique (user_id, device_id)
);

-- Reserved for a login-lockout Edge Function. No policy on purpose: only the service role touches it.
create table login_attempts (
  phone text primary key,
  failed_count integer not null default 0,
  locked_until timestamptz
);

-- indexes for the columns RLS and the pages filter on
create index on patient_doctors (doctor_id);
create index on patient_caregivers (caregiver_id);
create index on medication_plans (patient_id);
create index on medication_schedules (plan_id);
create index on medication_logs (plan_id, scheduled_at);
create index on appointments (patient_id, appointment_at);
create index on follow_ups (patient_id);
create index on notifications (user_id);

-- ---------- helper functions (security definer: they read user_roles/patients without RLS recursion) ----------
create function has_role(r app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles where user_id = auth.uid() and role = r)
$$;

create function is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_active from profiles where id = auth.uid()), false)
$$;

-- who may read a patient: admin, the patient, an assigned doctor, a confirmed caregiver
create function can_see_patient(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_active_user() and (
    has_role('admin')
    or exists (select 1 from patients p where p.id = pid and p.user_id = auth.uid())
    or exists (select 1 from patient_doctors pd join doctors d on d.id = pd.doctor_id
               where pd.patient_id = pid and pd.active and d.user_id = auth.uid())
    or exists (select 1 from patient_caregivers pc join caregivers c on c.id = pc.caregiver_id
               where pc.patient_id = pid and pc.status = 'confirmed' and pc.revoked_at is null
                 and c.user_id = auth.uid())
  )
$$;

-- who may edit plans/appointments: admin, an assigned doctor, a caregiver with can_manage_plan
create function can_manage_plan(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_active_user() and (
    has_role('admin')
    or exists (select 1 from patient_doctors pd join doctors d on d.id = pd.doctor_id
               where pd.patient_id = pid and pd.active and d.user_id = auth.uid())
    or exists (select 1 from patient_caregivers pc join caregivers c on c.id = pc.caregiver_id
               where pc.patient_id = pid and pc.status = 'confirmed' and pc.revoked_at is null
                 and pc.can_manage_plan and c.user_id = auth.uid())
  )
$$;

revoke execute on function has_role(app_role), is_active_user(), can_see_patient(uuid), can_manage_plan(uuid) from public, anon;
grant execute on function has_role(app_role), is_active_user(), can_see_patient(uuid), can_manage_plan(uuid) to authenticated;

-- every new auth user gets a profile; the web login sends full_name and phone as user metadata
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'phone');
  return new;
end
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- grants + row level security ----------
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on login_attempts from authenticated;

alter table profiles enable row level security;
alter table user_roles enable row level security;
alter table patients enable row level security;
alter table doctors enable row level security;
alter table caregivers enable row level security;
alter table patient_doctors enable row level security;
alter table patient_caregivers enable row level security;
alter table medicines enable row level security;
alter table medication_plans enable row level security;
alter table medication_schedules enable row level security;
alter table medication_logs enable row level security;
alter table appointments enable row level security;
alter table audit_logs enable row level security;
alter table bmi_logs enable row level security;
alter table follow_ups enable row level security;
alter table consents enable row level security;
alter table notifications enable row level security;
alter table device_tokens enable row level security;
alter table login_attempts enable row level security;

create policy profiles_r on profiles for select to authenticated using (id = auth.uid() or has_role('admin'));
create policy profiles_u on profiles for update to authenticated using (has_role('admin'));

create policy roles_r on user_roles for select to authenticated using (user_id = auth.uid() or has_role('admin'));
create policy roles_w on user_roles for all to authenticated using (has_role('admin')) with check (has_role('admin'));

create policy patients_r on patients for select to authenticated using (can_see_patient(id));
create policy patients_u_doctor on patients for update to authenticated using (can_manage_plan(id)) with check (can_manage_plan(id));
create policy patients_w on patients for all to authenticated using (has_role('admin')) with check (has_role('admin'));

create policy doctors_r on doctors for select to authenticated using (true);
create policy doctors_w on doctors for all to authenticated
  using (has_role('admin') or user_id = auth.uid()) with check (has_role('admin') or user_id = auth.uid());

create policy cg_r on caregivers for select to authenticated
  using (user_id = auth.uid() or has_role('admin') or has_role('doctor'));
create policy cg_w on caregivers for all to authenticated using (has_role('admin')) with check (has_role('admin'));

create policy pd_r on patient_doctors for select to authenticated using (can_see_patient(patient_id));
create policy pd_w on patient_doctors for all to authenticated using (has_role('admin')) with check (has_role('admin'));

create policy pc_r on patient_caregivers for select to authenticated using (can_see_patient(patient_id));
create policy pc_w on patient_caregivers for all to authenticated using (has_role('admin')) with check (has_role('admin'));
create policy pc_revoke on patient_caregivers for update to authenticated
  using (exists (select 1 from patients p where p.id = patient_id and p.user_id = auth.uid()));

create policy med_r on medicines for select to authenticated using (true);
create policy med_w on medicines for all to authenticated
  using (has_role('admin') or has_role('doctor')) with check (has_role('admin') or has_role('doctor'));

create policy plan_r on medication_plans for select to authenticated using (can_see_patient(patient_id));
create policy plan_w on medication_plans for all to authenticated
  using (can_manage_plan(patient_id)) with check (can_manage_plan(patient_id));

create policy sched_r on medication_schedules for select to authenticated
  using (exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id)));
create policy sched_w on medication_schedules for all to authenticated
  using (exists (select 1 from medication_plans p where p.id = plan_id and can_manage_plan(p.patient_id)))
  with check (exists (select 1 from medication_plans p where p.id = plan_id and can_manage_plan(p.patient_id)));

create policy log_r on medication_logs for select to authenticated
  using (exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id)));
create policy log_i on medication_logs for insert to authenticated
  with check (exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id)));
-- admin: any time. Patient/caregiver: within 24h of the scheduled time. Doctors: read only.
create policy log_u on medication_logs for update to authenticated
  using (
    exists (select 1 from medication_plans p where p.id = plan_id and can_see_patient(p.patient_id))
    and (has_role('admin') or (not has_role('doctor') and now() < scheduled_at + interval '24 hours'))
  );

create policy appt_r on appointments for select to authenticated using (can_see_patient(patient_id));
create policy appt_w on appointments for all to authenticated
  using (can_manage_plan(patient_id)) with check (can_manage_plan(patient_id));
create policy appt_confirm on appointments for update to authenticated
  using (exists (select 1 from patients p where p.id = patient_id and p.user_id = auth.uid()));

create policy audit_i on audit_logs for insert to authenticated with check (actor = auth.uid());
create policy audit_r on audit_logs for select to authenticated using (has_role('admin'));

create policy bmi_r on bmi_logs for select to authenticated using (can_see_patient(patient_id));
create policy bmi_i on bmi_logs for insert to authenticated with check (can_see_patient(patient_id));

-- patient-only accounts must not read the clinical follow-up notes
create policy fu_r on follow_ups for select to authenticated
  using (can_see_patient(patient_id) and (has_role('admin') or has_role('doctor') or has_role('caregiver')));
create policy fu_i on follow_ups for insert to authenticated with check (can_manage_plan(patient_id));

create policy consents_r on consents for select to authenticated using (user_id = auth.uid() or has_role('admin'));
create policy consents_i on consents for insert to authenticated with check (user_id = auth.uid() or given_by = auth.uid());

create policy notif_r on notifications for select to authenticated using (user_id = auth.uid() and is_active_user());
create policy notif_u on notifications for update to authenticated using (user_id = auth.uid());

create policy dev_r on device_tokens for select to authenticated using (user_id = auth.uid() or has_role('admin'));
create policy dev_i on device_tokens for insert to authenticated with check (user_id = auth.uid());
create policy dev_u on device_tokens for update to authenticated using (user_id = auth.uid());
create policy dev_d on device_tokens for delete to authenticated using (user_id = auth.uid());

-- ---------- add_patient: a doctor adds a patient without the Admin ----------
-- RLS only lets Admin write patients/patient_doctors. This function checks the caller itself,
-- creates the patient and assigns the calling doctor in one transaction, so the doctor can see the new patient.
create function add_patient(p_full_name text, p_age integer, p_gender text, p_conditions text, p_drug_allergies text, p_phone text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  did uuid;
  pid uuid;
begin
  if not is_active_user() or not (has_role('doctor') or has_role('admin')) then
    raise exception 'ไม่มีสิทธิ์เพิ่มผู้ป่วย' using errcode = '42501';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'กรุณาระบุชื่อ-นามสกุล' using errcode = '22023';
  end if;
  if p_age is not null and (p_age < 0 or p_age > 130) then
    raise exception 'อายุไม่ถูกต้อง' using errcode = '22023';
  end if;

  select id into did from doctors where user_id = auth.uid() and is_active limit 1;
  if did is null and not has_role('admin') then
    raise exception 'บัญชีแพทย์นี้ยังไม่มีข้อมูลแพทย์ในระบบ' using errcode = '42501';
  end if;

  insert into patients (full_name, age, gender, conditions, drug_allergies, phone)
  values (trim(p_full_name), p_age, nullif(trim(p_gender), ''), nullif(trim(p_conditions), ''),
          nullif(trim(p_drug_allergies), ''), nullif(trim(p_phone), ''))
  returning id into pid;

  if did is not null then
    insert into patient_doctors (patient_id, doctor_id, is_primary) values (pid, did, true);
  end if;
  insert into audit_logs (actor, action, table_name, row_id, new_value)
  values (auth.uid(), 'add_patient', 'patients', pid::text, jsonb_build_object('full_name', trim(p_full_name)));
  return pid;
end
$$;
revoke execute on function add_patient(text, integer, text, text, text, text) from public, anon;
grant execute on function add_patient(text, integer, text, text, text, text) to authenticated;

-- ---------- first admin ----------
-- 1) Authentication > Users > Add user: email <phone>@caredose.local, password = 6-digit PIN, tick "Auto Confirm User".
--    Under "User Metadata" add {"full_name": "ผู้ดูแลระบบ", "phone": "<phone>"}.
-- 2) Then run (replace the phone):
-- insert into user_roles (user_id, role)
--   select id, 'admin' from auth.users where email = '0812345678@caredose.local';
