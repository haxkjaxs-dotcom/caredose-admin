import { useEffect, useState, type FormEvent, type ReactNode } from 'react'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from '../supabase'
import type { Tone } from '../data'
import { Badge, Btn, Card, Field, H, Modal, Search, Select, Stat, Table, fmt, inputCls, tones } from '../ui'
import type { Ctx, FollowUp, Role } from '../ctx'
import { isThaiMobile, normalizePhoneDigits, samePhoneGroups, planRowToView, type PlanRow, type PlanView } from '../lib/plans'
import { SendNotice } from './SendNotice'

export type DoseStatus = 'ทานแล้ว' | 'เลท' | 'พลาดยา' | 'ยังไม่ได้บันทึก' | 'รอ sync' | 'ยังไม่ถึงกำหนด'
export type DoseItem = { id: string; date: string; med: string; scheduled: string; recorded: string; status: DoseStatus }

const doseTone: Record<DoseStatus, Tone> = {
  ทานแล้ว: 'green', เลท: 'yellow', พลาดยา: 'red', ยังไม่ได้บันทึก: 'gray', 'รอ sync': 'yellow', ยังไม่ถึงกำหนด: 'gray',
}
const dateKey = (d: Date) => {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
const addDays = (d: Date, amount: number) => {
  const next = new Date(d)
  next.setDate(next.getDate() + amount)
  return next
}
const thaiDate = (d: Date) => d.toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })
const hhmm = (d: Date) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
type LogRow = { scheduled_at: string; status: 'pending' | 'taken' | 'skipped' | 'missed'; taken_at: string | null; is_late: boolean; medication_plans: { medicines: { generic_name: string; trade_name: string | null } | null } | null }
// a real medication_logs row -> what the calendar shows
const toDoseItem = (r: LogRow, i: number): DoseItem => {
  const at = new Date(r.scheduled_at)
  const status: DoseStatus = r.status === 'taken' ? (r.is_late ? 'เลท' : 'ทานแล้ว') : r.status === 'pending' ? (at > new Date() ? 'ยังไม่ถึงกำหนด' : 'ยังไม่ได้บันทึก') : 'พลาดยา'
  const m = r.medication_plans?.medicines
  return { id: `${r.scheduled_at}-${i}`, date: dateKey(at), med: m?.trade_name || m?.generic_name || '-', scheduled: hhmm(at), recorded: r.taken_at ? hhmm(new Date(r.taken_at)) : '-', status }
}

type PatientRow = {
  id: string; full_name: string; age: number | null; gender: string | null; conditions: string | null
  drug_allergies: string | null; phone: string | null; user_id: string | null; nickname: string | null
  patient_doctors: { active: boolean; doctors: { full_name: string } | null }[]
}
const PATIENT_COLS = 'id, full_name, age, gender, conditions, drug_allergies, phone, user_id, nickname, patient_doctors(active, doctors(full_name))'
const doctorNames = (p: PatientRow) => p.patient_doctors.filter((x) => x.active).map((x) => x.doctors?.full_name).filter(Boolean).join(', ') || '-'
const DUP_PHONE = 'เบอร์ซ้ำกับผู้ป่วยคนอื่น ผู้ป่วยจะเข้าแอปไม่ได้จนกว่าจะแก้เบอร์'
const blank = { full_name: '', age: '', gender: 'หญิง', conditions: '', drug_allergies: '', phone: '', pin: '' }

export function Patients({ openPatient, notify, role }: Ctx) {
  const readOnly = role === 'Caregiver' // cosmetic: the database decides; detail page uses mock data so relatives get no "เปิด"
  const [rows, setRows] = useState<PatientRow[]>([])
  const [withPlan, setWithPlan] = useState<Set<string>>(new Set())
  const [q, setQ] = useState('')
  const [st, setSt] = useState('')
  const [form, setForm] = useState(false)
  const [f, setF] = useState(blank)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  // RLS decides the list: a doctor gets only the patients assigned to them, Admin gets all.
  const load = async (quiet = false) => {
    const [p, pl] = await Promise.all([
      supabase.from('patients').select(PATIENT_COLS).order('full_name'),
      supabase.from('medication_plans').select('patient_id').eq('status', 'active'),
    ])
    const bad = p.error ?? pl.error
    if (bad) return quiet ? undefined : notify('โหลดผู้ป่วยไม่สำเร็จ: ' + bad.message)
    setRows((p.data ?? []) as unknown as PatientRow[])
    setWithPlan(new Set((pl.data ?? []).map((x) => x.patient_id as string)))
  }
  // Patients fill in their own profile (conditions, age) from the app: refresh so Admin sees it without reloading.
  // shortcut: polling every 15 s, switch to Realtime on patients if this list gets large.
  useEffect(() => {
    load()
    const refresh = () => { if (!document.hidden) load(true) }
    const t = setInterval(refresh, 15000)
    window.addEventListener('focus', refresh)
    return () => { clearInterval(t); window.removeEventListener('focus', refresh) }
  }, [])

  const add = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    const age = f.age.trim() === '' ? null : Number(f.age)
    if (!f.full_name.trim()) return setErr('กรุณาระบุชื่อ-นามสกุล')
    if (age !== null && (!Number.isInteger(age) || age < 0 || age > 130)) return setErr('อายุต้องเป็นจำนวนเต็ม 0-130')
    if (!isThaiMobile(f.phone)) return setErr('กรุณากรอกเบอร์มือถือ 10 หลัก (ใช้เบอร์นี้ให้ผู้ป่วยเข้าแอป)')
    if (!/^\d{6}$/.test(f.pin)) return setErr('กรุณากำหนด PIN 6 หลักให้ผู้ป่วยเข้าสู่ระบบ')
    const phone = normalizePhoneDigits(f.phone)
    // a patient made from the Users page already has a row with this phone: block a second one (the login would clash anyway)
    const same = rows.find((p) => normalizePhoneDigits(p.phone ?? '') === phone)
    if (same) return setErr(`มีผู้ป่วยเบอร์นี้แล้ว: ${same.full_name} ไม่ต้องเพิ่มซ้ำ`)
    setBusy(true)
    setErr('')
    const { data: pid, error } = await supabase.rpc('add_patient', {
      p_full_name: f.full_name, p_age: age, p_gender: f.gender, p_conditions: f.conditions, p_drug_allergies: f.drug_allergies, p_phone: phone,
    })
    if (error) {
      setBusy(false)
      return setErr('บันทึกไม่สำเร็จ: ' + error.message)
    }
    // also creates the patient login (phone + PIN) and links it (create-user accepts Admin and doctor for role patient)
    {
      const acc = await supabase.functions.invoke('create-user', { body: { username: phone, full_name: f.full_name.trim(), pin: f.pin, role: 'patient', patient_id: pid } })
      if (acc.error) {
        const body = acc.error instanceof FunctionsHttpError ? await acc.error.context.json().catch(() => null) : null
        setBusy(false)
        load()
        return setErr('เพิ่มผู้ป่วยแล้ว แต่สร้างบัญชีไม่สำเร็จ: ' + (body?.error ?? acc.error.message))
      }
    }
    setBusy(false)
    setForm(false)
    setF(blank)
    notify('เพิ่มผู้ป่วยและสร้างบัญชีแล้ว')
    load()
  }

  // the DB trigger (integration.sql 20) carries the new name to the linked account, so the Users page shows it too
  const rename = async (p: PatientRow) => {
    const name = window.prompt('ชื่อ-นามสกุลใหม่', p.full_name)?.trim()
    if (!name || name === p.full_name) return
    const { data, error } = await supabase.from('patients').update({ full_name: name }).eq('id', p.id).select('id')
    if (error) return notify('แก้ชื่อไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('แก้ชื่อไม่สำเร็จ: ไม่มีสิทธิ์')
    notify('แก้ชื่อแล้ว')
    load()
  }

  // cascades to plans, schedules, adherence logs, appointments and links, so the confirm spells that out
  const remove = async (p: PatientRow) => {
    if (!window.confirm(`ลบผู้ป่วย "${p.full_name}" ถาวร?\nแผนยา ประวัติการทานยา นัดหมาย และการผูกญาติ/ผู้ดูแลของผู้ป่วยรายนี้จะถูกลบทั้งหมด กู้คืนไม่ได้`)) return
    // select() so a delete that RLS silently filtered out (0 rows) is reported, not shown as success
    const { data, error } = await supabase.from('patients').delete().eq('id', p.id).select('id')
    if (error) return notify('ลบผู้ป่วยไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('ลบผู้ป่วยไม่สำเร็จ: ไม่มีสิทธิ์')
    notify('ลบผู้ป่วยแล้ว')
    load()
  }

  const dupIds = samePhoneGroups(rows)
  const typed = normalizePhoneDigits(f.phone)
  const typedDup = typed !== '' && rows.some((p) => normalizePhoneDigits(p.phone ?? '') === typed)
  const shown = rows.filter((p) => p.full_name.includes(q) && (!st || (st === 'active') === withPlan.has(p.id)))
  return (
    <>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Stat label="ผู้ป่วยทั้งหมด" value={rows.length} tone="gray" />
        <Stat label="มีแผนยาใช้งาน" value={rows.filter((p) => withPlan.has(p.id)).length} tone="green" />
        <Stat label="ยังไม่มีแผนยา" value={rows.filter((p) => !withPlan.has(p.id)).length} tone="yellow" />
      </div>
      <Card>
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
          <Search v={q} set={setQ} ph="ค้นหาชื่อผู้ป่วย" />
          <Select v={st} set={setSt} all="ทุกสถานะ" opts={[['active', 'มีแผนยา'], ['none', 'ยังไม่มีแผนยา']]} />
          {!readOnly && <div className="sm:ml-auto"><Btn onClick={() => setForm(true)}>เพิ่มผู้ป่วย</Btn></div>}
        </div>
        <Table
          head={['ชื่อ-นามสกุล', 'อายุ/เพศ', 'โรคประจำตัว', 'แพ้ยา', 'ผู้ดูแลภาพรวม', 'แผนยา', 'เชื่อมแอป', '']}
          rows={shown.map((p) => [
            <b>{p.full_name}</b>, `${p.age ?? '-'} / ${p.gender ?? '-'}`, p.conditions ?? '-',
            p.drug_allergies ? <span className="font-medium text-red-700">{p.drug_allergies}</span> : <span className="text-slate-400">ไม่ระบุ</span>,
            doctorNames(p), <Badge tone={withPlan.has(p.id) ? 'green' : 'gray'}>{withPlan.has(p.id) ? 'มีแผนยา' : 'ไม่มีแผนยา'}</Badge>,
            <div><Badge tone={p.user_id ? 'green' : 'gray'}>{p.user_id ? 'เชื่อมแล้ว' : 'ยังไม่เชื่อม'}</Badge>{dupIds.has(p.id) && <div className="mt-1 text-xs text-amber-700">{DUP_PHONE}</div>}</div>,
            readOnly ? '' : (
              <div className="flex gap-2">
                <Btn kind="ghost" onClick={() => openPatient(p.id)}>เปิด</Btn>
                <Btn kind="ghost" onClick={() => rename(p)}>แก้ชื่อ</Btn>
                {role === 'Admin' && <Btn kind="danger" onClick={() => remove(p)}>ลบ</Btn>}{/* cosmetic: patients_w decides */}
              </div>
            ),
          ])}
        />
      </Card>
      {form && (
        <Modal title="เพิ่มผู้ป่วย" onClose={() => setForm(false)}>
          <form onSubmit={add} className="space-y-4">
            <Field label="ชื่อ-นามสกุล *"><input className={inputCls} value={f.full_name} onChange={(e) => setF({ ...f, full_name: e.target.value })} /></Field>
            <div className="grid gap-4 sm:grid-cols-3">
              <Field label="อายุ (ปี)"><input className={inputCls} type="number" min={0} max={130} step={1} value={f.age} onChange={(e) => setF({ ...f, age: e.target.value })} /></Field>
              <Field label="เพศ">
                <select className={inputCls} value={f.gender} onChange={(e) => setF({ ...f, gender: e.target.value })}>
                  {['หญิง', 'ชาย', 'อื่น ๆ'].map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
              <Field label="เบอร์โทร *">
                <input className={inputCls} inputMode="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} />
                {typedDup && <div className="mt-1 text-xs text-amber-700">{DUP_PHONE}</div>}
              </Field>
            </div>
            <Field label="โรคประจำตัว"><input className={inputCls} value={f.conditions} onChange={(e) => setF({ ...f, conditions: e.target.value })} /></Field>
            <Field label="ประวัติแพ้ยา"><input className={inputCls} value={f.drug_allergies} onChange={(e) => setF({ ...f, drug_allergies: e.target.value })} /></Field>
            {(
              <Field label="PIN 6 หลัก (สร้างบัญชีให้ผู้ป่วย ใช้เบอร์โทรเป็นชื่อผู้ใช้) *">
                <input className={inputCls} inputMode="numeric" maxLength={6} value={f.pin} onChange={(e) => setF({ ...f, pin: e.target.value.replace(/\D/g, '') })} />
              </Field>
            )}
            <p className="text-sm text-slate-500">ผู้ป่วยที่เพิ่มโดยผู้ดูแลภาพรวมจะอยู่ในความดูแลของผู้ดูแลภาพรวมคนนั้นโดยอัตโนมัติ</p>
            {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
            <div className="flex justify-end"><Btn>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
          </form>
        </Modal>
      )}
    </>
  )
}

export function PatientDetail({ id, back, followUps, setFollowUps, notify, role }: Ctx & { id: string; back: () => void }) {
  const [p, setP] = useState<PatientRow | null | undefined>(undefined)
  const [plans, setPlans] = useState<PlanView[]>([])
  const [next, setNext] = useState<{ appointment_at: string; place: string | null; reason: string | null } | null>(null)
  const [sending, setSending] = useState(false)
  useEffect(() => {
    supabase.from('patients').select(PATIENT_COLS).eq('id', id).maybeSingle().then(({ data, error }) => {
      if (error) notify('โหลดข้อมูลผู้ป่วยไม่สำเร็จ: ' + error.message)
      setP((data as unknown as PatientRow | null) ?? null)
    })
    supabase.from('medication_plans')
      .select('id, medicine_id, dose, meal_relation, start_date, end_date, status, doctor_note, medicines(generic_name, trade_name), medication_schedules(time_of_day, days_of_week, interval_days)')
      .eq('patient_id', id).eq('status', 'active').order('start_date', { ascending: false })
      .then(({ data }) => setPlans(((data ?? []) as unknown as PlanRow[]).map(planRowToView)))
    supabase.from('appointments').select('appointment_at, place, reason').eq('patient_id', id).in('status', ['pending', 'scheduled']).gte('appointment_at', new Date().toISOString())
      .order('appointment_at').limit(1).then(({ data }) => setNext(data?.[0] ?? null))
  }, [id])
  if (p === undefined) return <div className="text-slate-400">กำลังโหลด...</div>
  if (p === null) return <div className="space-y-4"><Btn kind="ghost" onClick={back}>กลับ</Btn><div className="text-slate-500">ไม่พบข้อมูลผู้ป่วย หรือไม่มีสิทธิ์เข้าถึง</div></div>

  const info: [string, ReactNode][] = [
    ['อายุ / เพศ', `${p.age ?? '-'} ปี / ${p.gender ?? '-'}`], ['โรคประจำตัว', p.conditions ?? '-'],
    ['เบอร์โทร', p.phone ?? '-'], ['ผู้ดูแลภาพรวม', doctorNames(p)],
  ]
  return (
    <>
      <div className="flex items-center gap-3">
        <Btn kind="ghost" onClick={back}>กลับ</Btn>
        <h2 className="text-2xl font-bold">{p.full_name}</h2>
        {role === 'Admin' && p.user_id && <div className="ml-auto"><Btn kind="ghost" onClick={() => setSending(true)}>ส่งข้อความ</Btn></div>}
      </div>
      {sending && <SendNotice patientId={p.id} patientName={p.full_name} notify={notify} onClose={() => setSending(false)} />}
      {p.drug_allergies && (
        <div className="rounded-2xl border border-red-300 bg-red-50 p-4 text-red-800">
          <b>ประวัติแพ้ยา / ข้อควรระวัง:</b> {p.drug_allergies}
        </div>
      )}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <H>ข้อมูลส่วนตัว</H>
          <dl className="space-y-2">{info.map(([k, v]) => (<div key={k} className="flex justify-between gap-4 border-b border-slate-100 pb-2"><dt className="text-slate-500">{k}</dt><dd className="text-right font-medium">{v}</dd></div>))}</dl>
        </Card>
        <Card>
          <H>นัดหมายครั้งถัดไป</H>
          {next ? <div><div className="font-semibold">{fmt(next.appointment_at)}</div><div className="text-slate-500">{next.place ?? '-'} · {next.reason ?? '-'}</div></div> : <div className="text-slate-400">ไม่มีนัดหมาย</div>}
        </Card>
      </div>
      <Card>
        <H>แผนยาปัจจุบัน</H>
        <Table head={['ยา', 'ขนาด', 'เวลา', 'คำแนะนำ', 'ช่วงเวลา']} rows={plans.map((r) => [r.name, r.dose, r.times.join(', ') || '-', r.meal || '-', r.range])} />
      </Card>
      <MedicationAdherence patient={id} followUps={followUps} setFollowUps={setFollowUps} notify={notify} role={role} />
    </>
  )
}

export function MedicationAdherence({
  patient, followUps, setFollowUps, notify, role,
}: {
  patient: string; followUps: FollowUp[]; setFollowUps: (items: FollowUp[]) => void
  notify: (message: string) => void; role: Role
}) {
  const [view, setView] = useState<'week' | 'month'>('week')
  const [offset, setOffset] = useState(0)
  const [selected, setSelected] = useState(dateKey(new Date()))
  const [note, setNote] = useState('')
  const anchor = new Date()
  let start: Date
  let end: Date
  if (view === 'week') {
    const base = addDays(anchor, offset * 7)
    const mondayOffset = (base.getDay() + 6) % 7
    start = addDays(base, -mondayOffset)
    end = addDays(start, 6)
  } else {
    const base = new Date(anchor.getFullYear(), anchor.getMonth() + offset, 1)
    start = base
    end = new Date(base.getFullYear(), base.getMonth() + 1, 0)
  }
  const days: Date[] = []
  for (let day = new Date(start); day <= end; day = addDays(day, 1)) days.push(day)
  const [items, setItems] = useState<DoseItem[]>([])
  const from = dateKey(start)
  const to = dateKey(end)
  // real medication_logs of this patient in the shown range; re-read every 15 s so a dose the patient just marked as taken appears
  useEffect(() => {
    const read = async () => {
      const { data, error } = await supabase.from('medication_logs')
        .select('scheduled_at, status, taken_at, is_late, medication_plans!inner(patient_id, medicines(generic_name, trade_name))')
        .eq('medication_plans.patient_id', patient)
        .gte('scheduled_at', new Date(`${from}T00:00:00`).toISOString()).lt('scheduled_at', addDays(new Date(`${to}T00:00:00`), 1).toISOString())
        .order('scheduled_at')
      if (error) return notify('โหลดการทานยาไม่สำเร็จ: ' + error.message)
      setItems(((data ?? []) as unknown as LogRow[]).map(toDoseItem))
    }
    read()
    const t = setInterval(() => { if (!document.hidden) read() }, 15000)
    return () => clearInterval(t)
  }, [patient, from, to])
  const due = items.filter((item) => item.status !== 'ยังไม่ถึงกำหนด')
  const taken = due.filter((item) => item.status === 'ทานแล้ว' || item.status === 'เลท').length
  const missed = due.filter((item) => item.status === 'พลาดยา').length
  const pending = due.filter((item) => item.status === 'ยังไม่ได้บันทึก' || item.status === 'รอ sync').length
  const percentage = due.length ? Math.round((taken / due.length) * 100) : 0
  const selectedItems = items.filter((item) => item.date === selected)
  const dailyStatus = (date: string) => {
    const list = items.filter((item) => item.date === date)
    if (!list.length) return { label: 'ไม่มีแผนยา', tone: 'gray' as Tone }
    if (list.every((item) => item.status === 'ยังไม่ถึงกำหนด')) return { label: 'ยังไม่ถึงกำหนด', tone: 'gray' as Tone }
    if (list.some((item) => item.status === 'รอ sync')) return { label: 'รอ sync', tone: 'yellow' as Tone }
    if (list.some((item) => item.status === 'พลาดยา')) return { label: 'พลาดยา', tone: 'red' as Tone }
    if (list.some((item) => item.status === 'ยังไม่ได้บันทึก')) return { label: 'ทานไม่ครบ', tone: 'yellow' as Tone }
    return { label: 'ทานครบ', tone: 'green' as Tone }
  }
  const saveFollowUp = () => {
    if (!note.trim()) return notify('กรุณาระบุผลการติดตาม')
    const by = role === 'Doctor' ? 'นพ.สมชาย วงศ์สกุล' : 'ผู้ดูแลระบบ'
    setFollowUps([{ id: `f${Date.now()}`, patient, note: note.trim(), at: '12 มิ.ย. 2568 14:30', by }, ...followUps])
    setNote('')
    notify('บันทึกผลการติดตามแล้ว')
  }

  return (
    <Card>
      <H action={<Select v={view} set={(value) => { setView((value || 'week') as 'week' | 'month'); setOffset(0) }} all="รายสัปดาห์" opts={[['month', 'รายเดือน']]} />}>
        การทานยา
      </H>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 p-3">
        <Btn kind="ghost" onClick={() => setOffset(offset - 1)}>ช่วงก่อนหน้า</Btn>
        <div className="text-center">
          <div className="font-semibold">{thaiDate(start)} – {thaiDate(end)}</div>
          <div className="text-sm text-slate-500">คำนวณเฉพาะรายการที่ถึงกำหนดและพ้นช่วงเวลารอแล้ว ไม่รวมรายการอนาคต</div>
        </div>
        <Btn kind="ghost" onClick={() => setOffset(offset + 1)}>ช่วงถัดไป</Btn>
      </div>
      <div className="mb-5 grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl bg-emerald-50 p-4 ring-1 ring-emerald-200">
          <div className="text-sm text-emerald-800">ทานแล้ว</div>
          <div className="text-2xl font-bold text-emerald-900">{taken} จาก {due.length} รายการ ({percentage}%)</div>
        </div>
        <div className="rounded-xl bg-red-50 p-4 ring-1 ring-red-200">
          <div className="text-sm text-red-700">พลาดยา</div>
          <div className="text-2xl font-bold text-red-800">{missed} รายการ</div>
        </div>
        <div className="rounded-xl bg-amber-50 p-4 ring-1 ring-amber-200">
          <div className="text-sm text-amber-800">ยังรอตรวจสอบ / รอ sync</div>
          <div className="text-2xl font-bold text-amber-900">{pending} รายการ</div>
        </div>
      </div>
      <div className={`grid gap-2 ${view === 'week' ? 'grid-cols-2 sm:grid-cols-4 lg:grid-cols-7' : 'grid-cols-3 sm:grid-cols-5 lg:grid-cols-7'}`}>
        {days.map((day) => {
          const key = dateKey(day)
          const status = dailyStatus(key)
          return (
            <button
              key={key}
              onClick={() => setSelected(key)}
              className={`min-h-24 rounded-xl border p-3 text-left transition ${selected === key ? 'border-brand-600 ring-2 ring-brand-100' : 'border-slate-200 hover:bg-slate-50'}`}
            >
              <span className="block text-sm text-slate-500">{day.toLocaleDateString('th-TH', { weekday: 'short' })}</span>
              <span className="block text-lg font-semibold">{day.getDate()}</span>
              <span className={`mt-1 block rounded-lg px-2 py-1 text-xs font-medium ${tones[status.tone]}`}>{status.label}</span>
            </button>
          )
        })}
      </div>
      <div className="mt-6">
        <H>รายละเอียดวันที่ {thaiDate(new Date(`${selected}T12:00:00`))}</H>
        {selectedItems.length ? (
          <Table
            head={['ชื่อยา', 'เวลาที่กำหนด', 'เวลาที่บันทึกจริง', 'สถานะ']}
            rows={selectedItems.map((item) => [item.med, item.scheduled, item.recorded, <Badge tone={doseTone[item.status]}>{item.status}</Badge>])}
          />
        ) : (
          <div className="rounded-xl bg-slate-50 p-4 text-slate-600">ไม่มีแผนยาในวันนี้</div>
        )}
      </div>
      <div className="mt-6 border-t border-slate-200 pt-5">
        <H>บันทึกผลการติดตาม</H>
        <Field label="ผลการติดตาม / คำแนะนำ">
          <textarea className={inputCls + ' min-h-24 py-3'} value={note} onChange={(event) => setNote(event.target.value)} placeholder="เช่น ติดต่อผู้ป่วยแล้ว หรือให้คำแนะนำเรื่องการทานยาแล้ว" />
        </Field>
        <div className="mt-3 flex justify-end"><Btn onClick={saveFollowUp}>บันทึกผลการติดตาม</Btn></div>
        <div className="mt-4 space-y-3">
          {followUps.filter((item) => item.patient === patient).map((item) => (
            <div key={item.id} className="rounded-xl border border-slate-200 p-3">
              <div>{item.note}</div>
              <div className="mt-1 text-sm text-slate-500">{item.at} · บันทึกโดย {item.by}</div>
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
}
