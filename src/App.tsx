import { useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'
import * as D from './data'
import type { Appt } from './data'
import type { FollowUp, Role } from './ctx'
import { Dashboard } from './pages/Dashboard'
import { Patients, PatientDetail } from './pages/Patients'
import { Plans } from './pages/Plans'
import { Logs } from './pages/Logs'
import { Appts } from './pages/Appts'
import { Meds } from './pages/Meds'
import { Doctors } from './pages/Doctors'
import { Carers } from './pages/Carers'
import { Users } from './pages/Users'
import { Login } from './pages/Login'
import { defaultPageFor, navIdsFor, roleFromRoles } from './lib/roles'

type Nav = { id: string; label: string; admin?: boolean }
const NAV: Nav[] = [
  { id: 'dash', label: 'ภาพรวม' },
  { id: 'patients', label: 'ผู้ป่วย' },
  { id: 'plans', label: 'แผนยา' },
  { id: 'logs', label: 'ประวัติการทานยา' },
  { id: 'appts', label: 'นัดหมาย' },
  { id: 'meds', label: 'คลังยา' },
  { id: 'doctors', label: 'ผู้ดูแลภาพรวม' },
  { id: 'carers', label: 'ญาติและผู้ดูแล' },
  { id: 'users', label: 'ผู้ใช้และสิทธิ์' }, // Doctor sees it too, but may only edit caregiver / patient accounts
]

const signOut = () => supabase.auth.signOut()
const Centered = ({ children }: { children: React.ReactNode }) => (
  <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-4 text-center">{children}</div>
)

export default function App() {
  const [session, setSession] = useState<Session | null | undefined>(undefined)
  const [role, setRole] = useState<Role | 'none' | undefined>(undefined)
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])
  const uid = session?.user.id
  useEffect(() => {
    setRole(undefined)
    if (!uid) return
    Promise.all([
      supabase.from('user_roles').select('role').eq('user_id', uid),
      supabase.from('profiles').select('is_active').eq('id', uid).maybeSingle(),
    ]).then(([roles, prof]) => {
      const r = (roles.data ?? []).map((x) => x.role)
      // a disabled account is signed in but gets no access
      setRole(roleFromRoles(r, !!prof.data?.is_active))
    })
  }, [uid])

  if (session === undefined || (session && role === undefined)) return <Centered>กำลังโหลด...</Centered>
  if (!session) return <Login />
  if (role === 'none' || !role) {
    return (
      <Centered>
        <p>บัญชีนี้ไม่มีสิทธิ์เข้าหลังบ้าน (ต้องเป็น Admin ผู้ดูแลภาพรวม หรือญาติผู้ดูแล)</p>
        <button className="min-h-11 rounded-xl border border-slate-300 px-4" onClick={signOut}>ออกจากระบบ</button>
      </Centered>
    )
  }
  return <Shell role={role} />
}

function Shell({ role }: { role: Role }) {
  const [page, setPage] = useState(defaultPageFor(role))
  const [detail, setDetail] = useState<string | null>(null)
  const [detailReturn, setDetailReturn] = useState('patients')
  const [open, setOpen] = useState(false)
  const [plans, setPlans] = useState(D.plans)
  const [appts, setAppts] = useState(D.appts)
  const [followUps, setFollowUps] = useState<FollowUp[]>([])
  const [toast, setToast] = useState('')
  const me = 'd1' // shortcut: mock doctor id, replace with doctors.id of the signed-in user when pages read from Supabase
  const notify = (m: string) => { setToast(m); setTimeout(() => setToast(''), 2500) }
  const myPatients = useMemo(() => (role === 'Admin' ? D.patients : D.patients.filter((p) => p.doctor === me)), [role])
  const ids = new Set(myPatients.map((p) => p.id))
  const go = (p: string) => { setPage(p); setDetail(null); setOpen(false) }
  const allowed = navIdsFor(role, NAV)
  const nav = NAV.filter((n) => allowed.includes(n.id))
  const cur = allowed.includes(page) ? page : defaultPageFor(role) // a page outside the role's menu is never rendered
  const roleLabel = role === 'Admin' ? 'ผู้ดูแลระบบ' : role === 'Caregiver' ? 'ญาติผู้ดูแล (ดูอย่างเดียว)' : 'ผู้ดูแลภาพรวม'
  const ctx = {
    patients: myPatients, ids, plans, setPlans, appts: appts.filter((a) => ids.has(a.patient)),
    setAppts: (next: Appt[]) => setAppts([...appts.filter((a) => !ids.has(a.patient)), ...next]),
    followUps, setFollowUps, notify, role,
    openPatient: (id: string) => { setDetailReturn(page); setPage('patients'); setDetail(id) },
    go,
  }

  return (
    <div className="min-h-screen lg:flex">
      <aside className={`fixed inset-y-0 left-0 z-40 w-64 bg-brand-900 p-5 text-white transition lg:static lg:translate-x-0 ${open ? '' : '-translate-x-full'}`}>
        <div className="mb-8">
          <div className="text-2xl font-bold">ยาอุ่นใจ</div>
          <div className="text-sm text-brand-100">CareDose · ระบบหลังบ้าน</div>
        </div>
        <nav className="space-y-1">
          {nav.map((n) => (
            <button key={n.id} onClick={() => go(n.id)} className={`flex min-h-11 w-full items-center rounded-xl px-4 text-left text-base ${cur === n.id ? 'bg-white/15 font-semibold' : 'text-brand-100 hover:bg-white/10'}`}>
              {n.label}
            </button>
          ))}
        </nav>
        <div className="absolute inset-x-5 bottom-5 rounded-xl bg-white/10 p-3 text-sm">
          <div className="mb-2 text-brand-100">{roleLabel}</div>
          <button onClick={signOut} className="min-h-11 w-full rounded-lg bg-white px-2 py-2 text-brand-900">ออกจากระบบ</button>
        </div>
      </aside>
      {open && <div className="fixed inset-0 z-30 bg-black/30 lg:hidden" onClick={() => setOpen(false)} />}
      <main className="min-w-0 flex-1">
        <header className="sticky top-0 z-20 flex items-center gap-3 border-b border-slate-200 bg-white/90 px-4 py-3 backdrop-blur lg:px-8">
          <button className="min-h-11 rounded-xl border border-slate-300 px-4 lg:hidden" onClick={() => setOpen(true)}>เมนู</button>
          <h1 className="text-xl font-bold">{nav.find((n) => n.id === cur)?.label}</h1>
          <span className="ml-auto rounded-full bg-brand-50 px-3 py-1 text-sm text-brand-700">{role === 'Doctor' ? 'นพ.สมชาย วงศ์สกุล' : roleLabel}</span>
        </header>
        <div className="space-y-6 p-4 lg:p-8">
          {cur === 'dash' && <Dashboard {...ctx} />}
          {cur === 'patients' && (detail ? <PatientDetail id={detail} {...ctx} back={() => go(detailReturn)} /> : <Patients {...ctx} />)}
          {cur === 'plans' && <Plans {...ctx} />}
          {cur === 'logs' && <Logs {...ctx} />}
          {cur === 'appts' && <Appts {...ctx} />}
          {cur === 'meds' && <Meds {...ctx} />}
          {cur === 'doctors' && <Doctors {...ctx} />}
          {cur === 'carers' && <Carers {...ctx} />}
          {cur === 'users' && <Users role={role} />}
        </div>
      </main>
      {toast && <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-xl bg-brand-900 px-5 py-3 text-white shadow-lg">{toast}</div>}
    </div>
  )
}
