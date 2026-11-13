// Edge Function: an active Admin (any role) or ผู้ดูแลภาพรวม (caregiver / patient only) creates a login (username or phone + 6-digit PIN) and its role.
// Needs the service role key, so it cannot run in the browser. SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected by Supabase automatically.
import { createClient } from 'npm:@supabase/supabase-js@2'

const ROLES = ['admin', 'doctor', 'caregiver', 'patient']
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  // The caller must be a signed-in, active Admin or doctor.
  const token = req.headers.get('Authorization')?.replace('Bearer ', '') ?? ''
  const { data: { user } } = await admin.auth.getUser(token)
  if (!user) return reply({ error: 'ยังไม่ได้เข้าสู่ระบบ' }, 401)
  const [{ data: roles }, { data: prof }] = await Promise.all([
    admin.from('user_roles').select('role').eq('user_id', user.id),
    admin.from('profiles').select('is_active').eq('id', user.id).maybeSingle(),
  ])
  const isAdmin = !!roles?.some((r) => r.role === 'admin')
  if (!prof?.is_active || !(isAdmin || roles?.some((r) => r.role === 'doctor'))) return reply({ error: 'ไม่มีสิทธิ์สร้างบัญชี' }, 403)

  const { username, full_name, pin, role, patient_id } = await req.json().catch(() => ({}))
  if (!/^\w{3,30}$/.test(username ?? '') || !/^\d{6}$/.test(pin ?? '') || !String(full_name ?? '').trim() || !ROLES.includes(role)) {
    return reply({ error: 'ข้อมูลไม่ถูกต้อง (ชื่อผู้ใช้ 3-30 ตัว, PIN 6 หลัก, ต้องมีชื่อและสิทธิ์)' }, 400)
  }
  if (!isAdmin && role !== 'caregiver' && role !== 'patient') return reply({ error: 'ผู้ดูแลภาพรวมสร้างได้เฉพาะญาติ/ผู้ดูแล และผู้ป่วย' }, 403)
  // optional: link the new patient login to an existing, not yet linked patients row
  if (patient_id != null && (role !== 'patient' || !/^[0-9a-f-]{36}$/i.test(patient_id))) return reply({ error: 'patient_id ไม่ถูกต้อง' }, 400)
  const name = String(full_name).trim().slice(0, 100)

  // A patient login with a phone username links to the unlinked patients row with that phone. Checked BEFORE the account exists.
  // Two such rows (a family sharing one number) is ambiguous: refuse, like claim_my_patient, else the login could open another person's record.
  const digits = role === 'patient' && /^\d{9,10}$/.test(username) ? username : null
  let pid: string | null = patient_id ?? null
  if (!pid && digits) {
    const same = await admin.from('patients').select('id').eq('phone', digits).is('user_id', null).limit(2)
    if (same.error) return reply({ error: 'ตรวจสอบเบอร์ผู้ป่วยไม่สำเร็จ' }, 500)
    if (same.data.length > 1) return reply({ error: 'เบอร์นี้มีผู้ป่วยที่ยังไม่เชื่อมบัญชีมากกว่า 1 คน กรุณาแก้เบอร์ซ้ำก่อน' }, 409)
    pid = same.data[0]?.id ?? null
  }

  const { data, error } = await admin.auth.admin.createUser({
    email: `${username.toLowerCase()}@caredose.local`,
    password: pin,
    email_confirm: true,
    user_metadata: { full_name: name, phone: username },
  })
  if (error || !data.user) return reply({ error: error?.message ?? 'สร้างบัญชีไม่สำเร็จ' }, 400)
  const id = data.user.id

  // A doctor also needs a doctors row (else RLS shows them no patients), a caregiver a caregivers row (the Carers page lists those).
  const r1 = await admin.from('user_roles').insert({ user_id: id, role })
  const r2 = role === 'doctor' ? await admin.from('doctors').insert({ user_id: id, full_name: name })
    : role === 'caregiver' ? await admin.from('caregivers').insert({ user_id: id, full_name: name, phone: /^\d{9,10}$/.test(username) ? username : null })
    : { error: null }
  // profiles start disabled (security_fixes.sql), only accounts made here are switched on
  const r3 = await admin.from('profiles').update({ is_active: true }).eq('id', id)
  // A patient login always has a patients row (the Patients page lists those): link the one given, else the unlinked row with the same phone, else make one.
  // shortcut: phone match is exact digits, a row saved as "081-234-5678" is not found and a second row is made; normalise phones when that bites.
  let madePatient = false
  let r4: { error: unknown; data: unknown[] | null } = { error: null, data: [{}] }
  if (role === 'patient') {
    if (!pid) {
      const ins = await admin.from('patients').insert({ full_name: name, phone: digits }).select('id').single()
      pid = ins.data?.id ?? null
      madePatient = !!pid
      if (ins.error) r4 = { error: ins.error, data: null }
    }
    // .select() so "no unlinked patient with that id" (0 rows) counts as a failure and rolls the account back
    if (pid && !r4.error) r4 = await admin.from('patients').update({ user_id: id }).eq('id', pid).is('user_id', null).select('id')
  }
  if (r1.error || r2.error || r3.error || r4.error || !r4.data?.length) {
    if (madePatient) await admin.from('patients').delete().eq('id', pid!)
    await Promise.all([admin.from('doctors').delete().eq('user_id', id), admin.from('caregivers').delete().eq('user_id', id)]) // else user_id goes null and an orphan row stays
    await admin.auth.admin.deleteUser(id) // cascades profile + role, so no half-made account is left
    return reply({ error: 'ตั้งสิทธิ์ไม่สำเร็จ ยกเลิกการสร้างบัญชี' }, 500)
  }
  await admin.from('audit_logs').insert({ actor: user.id, action: 'create_user', table_name: 'auth.users', row_id: id, new_value: { username, role, patient_id: pid } })
  return reply({ id })
})
