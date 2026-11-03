// Edge Function: an active Admin creates a login (username or phone + 6-digit PIN) and its role.
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

  // The caller must be a signed-in, active Admin.
  const token = req.headers.get('Authorization')?.replace('Bearer ', '') ?? ''
  const { data: { user } } = await admin.auth.getUser(token)
  if (!user) return reply({ error: 'ยังไม่ได้เข้าสู่ระบบ' }, 401)
  const [{ data: roles }, { data: prof }] = await Promise.all([
    admin.from('user_roles').select('role').eq('user_id', user.id),
    admin.from('profiles').select('is_active').eq('id', user.id).maybeSingle(),
  ])
  if (!prof?.is_active || !roles?.some((r) => r.role === 'admin')) return reply({ error: 'ต้องเป็น Admin เท่านั้น' }, 403)

  const { username, full_name, pin, role } = await req.json().catch(() => ({}))
  if (!/^\w{3,30}$/.test(username ?? '') || !/^\d{6}$/.test(pin ?? '') || !String(full_name ?? '').trim() || !ROLES.includes(role)) {
    return reply({ error: 'ข้อมูลไม่ถูกต้อง (ชื่อผู้ใช้ 3-30 ตัว, PIN 6 หลัก, ต้องมีชื่อและสิทธิ์)' }, 400)
  }
  const name = String(full_name).trim().slice(0, 100)

  const { data, error } = await admin.auth.admin.createUser({
    email: `${username.toLowerCase()}@caredose.local`,
    password: pin,
    email_confirm: true,
    user_metadata: { full_name: name, phone: username },
  })
  if (error || !data.user) return reply({ error: error?.message ?? 'สร้างบัญชีไม่สำเร็จ' }, 400)
  const id = data.user.id

  // A doctor also needs a doctors row, otherwise RLS shows them no patients.
  const r1 = await admin.from('user_roles').insert({ user_id: id, role })
  const r2 = role === 'doctor' ? await admin.from('doctors').insert({ user_id: id, full_name: name }) : { error: null }
  // profiles start disabled (security_fixes.sql), only accounts made here are switched on
  const r3 = await admin.from('profiles').update({ is_active: true }).eq('id', id)
  if (r1.error || r2.error || r3.error) {
    await admin.auth.admin.deleteUser(id) // cascades profile + role, so no half-made account is left
    return reply({ error: 'ตั้งสิทธิ์ไม่สำเร็จ ยกเลิกการสร้างบัญชี' }, 500)
  }
  await admin.from('audit_logs').insert({ actor: user.id, action: 'create_user', table_name: 'auth.users', row_id: id, new_value: { username, role } })
  return reply({ id })
})
