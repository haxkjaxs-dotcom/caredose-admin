import { useState, type FormEvent } from 'react'
import { supabase } from '../supabase'
import { Btn, Card, Field, inputCls } from '../ui'

// Accounts are Supabase email users; the phone number or username maps to an internal address (see supabase/schema.sql).
const loginEmail = (id: string) => `${id.toLowerCase()}@caredose.local`

// shortcut: no lockout beyond Supabase's built-in rate limit, add a login Edge Function using login_attempts before real patient data.
export function Login() {
  const [phone, setPhone] = useState('')
  const [pin, setPin] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    if (!/^\w{3,30}$/.test(phone) || !/^\d{6}$/.test(pin)) return setErr('กรุณากรอกเบอร์โทรหรือชื่อผู้ใช้ (ตัวอักษร ตัวเลข _) และ PIN 6 หลัก')
    setBusy(true)
    setErr('')
    const { error } = await supabase.auth.signInWithPassword({ email: loginEmail(phone), password: pin })
    setBusy(false)
    if (error) setErr('เบอร์โทรหรือ PIN ไม่ถูกต้อง')
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <div className="mb-6 text-center">
          <div className="text-2xl font-bold text-brand-900">ยาอุ่นใจ</div>
          <div className="text-sm text-slate-500">CareDose · เข้าสู่ระบบหลังบ้าน</div>
        </div>
        <form onSubmit={submit} className="space-y-4">
          <Field label="เบอร์โทรศัพท์ หรือ ชื่อผู้ใช้">
            <input className={inputCls} autoComplete="username" maxLength={30} value={phone} onChange={(e) => setPhone(e.target.value.replace(/\W/g, ''))} />
          </Field>
          <Field label="PIN 6 หลัก">
            <input className={inputCls} type="password" inputMode="numeric" autoComplete="current-password" maxLength={6} value={pin} onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))} />
          </Field>
          {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
          <div className="[&>button]:w-full"><Btn>{busy ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ'}</Btn></div>
        </form>
      </Card>
    </div>
  )
}
