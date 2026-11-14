import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import type { Tone } from '../data'
import { Badge, Btn, Card, Field, Modal, Select, Table, fmt, inputCls } from '../ui'
import type { Ctx } from '../ctx'

// database status -> label shown on screen
const LABEL: Record<string, string> = { pending: 'รอนัด', scheduled: 'นัดแล้ว', done: 'มาตามนัด', postponed: 'เลื่อนนัด', cancelled: 'ยกเลิก' }
const TONE: Record<string, Tone> = { pending: 'yellow', scheduled: 'green', done: 'green', postponed: 'gray', cancelled: 'red' }
type Row = { id: string; patient_id: string; appointment_at: string; place: string | null; reason: string | null; status: string; patients: { full_name: string } | null; doctors: { full_name: string } | null }
type Opt = { id: string; full_name: string }
const blank = { doctor: '', at: '', place: '', reason: '' }

export function Appts({ notify, openPatient }: Ctx) {
  const [rows, setRows] = useState<Row[]>([])
  const [pats, setPats] = useState<Opt[]>([])
  const [docs, setDocs] = useState<Opt[]>([])
  const [form, setForm] = useState(false)
  const [st, setSt] = useState('')
  const [q, setQ] = useState('')
  const [pid, setPid] = useState('')
  const [f, setF] = useState(blank)
  const [busy, setBusy] = useState(false)

  const load = async () => {
    const [a, p, d] = await Promise.all([
      supabase.from('appointments').select('id, patient_id, appointment_at, place, reason, status, patients(full_name), doctors(full_name)').order('appointment_at'),
      supabase.from('patients').select('id, full_name').order('full_name'),
      supabase.from('doctors').select('id, full_name').eq('is_active', true).order('full_name'),
    ])
    const bad = a.error ?? p.error ?? d.error
    if (bad) return notify('โหลดนัดหมายไม่สำเร็จ: ' + bad.message)
    setRows((a.data ?? []) as unknown as Row[])
    setPats(p.data ?? [])
    setDocs(d.data ?? [])
  }
  useEffect(() => { load() }, [])

  const sugg = q && !pid ? pats.filter((p) => p.full_name.includes(q)) : []

  // select() so an update that RLS silently filtered out (0 rows) is reported, not shown as success
  const set = async (id: string, status: string) => {
    const { data, error } = await supabase.from('appointments').update({ status }).eq('id', id).select('id')
    if (error) return notify('อัปเดตไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('อัปเดตไม่สำเร็จ: ไม่มีสิทธิ์')
    notify(`อัปเดตสถานะเป็น "${LABEL[status]}"`)
    load()
  }

  const save = async () => {
    if (busy) return
    if (!pid) return notify('กรุณาเลือกผู้ป่วยจากรายการ')
    if (!f.at) return notify('กรุณาระบุวันที่และเวลา')
    setBusy(true)
    const { error } = await supabase.from('appointments').insert({
      patient_id: pid, doctor_id: f.doctor || null, appointment_at: new Date(f.at).toISOString(), place: f.place.trim() || null, reason: f.reason.trim() || null,
    })
    setBusy(false)
    if (error) return notify('สร้างนัดหมายไม่สำเร็จ: ' + error.message)
    setForm(false); setQ(''); setPid(''); setF(blank)
    notify('สร้างนัดหมายแล้ว')
    load()
  }

  return (
    <>
      <Card>
        <div className="mb-4 flex gap-3">
          <Select v={st} set={setSt} all="ทุกสถานะ" opts={Object.entries(LABEL).map(([k, l]) => [k, l])} />
          <div className="ml-auto"><Btn onClick={() => setForm(true)}>เพิ่มนัดหมาย</Btn></div>
        </div>
        <Table
          head={['ผู้ป่วย', 'ผู้ดูแลภาพรวม', 'วันที่และเวลา', 'สถานที่', 'เหตุผล', 'สถานะ', 'จัดการ']}
          rows={rows.filter((a) => !st || a.status === st).map((a) => [
            <button className="font-semibold text-brand-700 hover:underline" onClick={() => openPatient(a.patient_id)}>{a.patients?.full_name ?? '-'}</button>,
            a.doctors?.full_name ?? '-', fmt(a.appointment_at), a.place ?? '-', a.reason ?? '-', <Badge tone={TONE[a.status]}>{LABEL[a.status]}</Badge>,
            <div className="flex flex-wrap gap-2">
              <Btn kind="ghost" onClick={() => openPatient(a.patient_id)}>ดูประวัติการทานยา</Btn>
              {a.status !== 'scheduled' && <Btn kind="ghost" onClick={() => set(a.id, 'scheduled')}>นัดแล้ว</Btn>}
              {a.status !== 'done' && <Btn kind="ghost" onClick={() => set(a.id, 'done')}>มาตามนัด</Btn>}
              {a.status !== 'pending' && <Btn kind="ghost" onClick={() => set(a.id, 'pending')}>กลับเป็นรอนัด</Btn>}
              {a.status !== 'postponed' && <Btn kind="ghost" onClick={() => set(a.id, 'postponed')}>เลื่อน</Btn>}
              {a.status !== 'cancelled' && <Btn kind="danger" onClick={() => set(a.id, 'cancelled')}>ยกเลิก</Btn>}
            </div>,
          ])}
        />
      </Card>
      {form && (
        <Modal title="เพิ่มนัดหมาย" onClose={() => setForm(false)}>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="relative sm:col-span-2">
              <Field label="ผู้ป่วย (พิมพ์ชื่อเพื่อค้นหา)"><input className={inputCls} value={q} autoFocus onChange={(e) => { setQ(e.target.value); setPid('') }} /></Field>
              {sugg.length > 0 && (
                <ul className="absolute z-10 mt-1 w-full overflow-hidden rounded-xl border border-slate-200 bg-white shadow-lg">
                  {sugg.map((p) => <li key={p.id}><button className="min-h-11 w-full px-3 text-left hover:bg-brand-50" onClick={() => { setPid(p.id); setQ(p.full_name) }}>{p.full_name}</button></li>)}
                </ul>
              )}
              {q && !pid && !sugg.length && <div className="mt-1 text-sm text-slate-500">ไม่พบผู้ป่วยชื่อนี้</div>}
            </div>
            <Field label="ผู้ดูแลภาพรวม"><select className={inputCls} value={f.doctor} onChange={(e) => setF({ ...f, doctor: e.target.value })}><option value="">- ไม่ระบุ -</option>{docs.map((d) => <option key={d.id} value={d.id}>{d.full_name}</option>)}</select></Field>
            <Field label="วันที่และเวลา *"><input type="datetime-local" className={inputCls} value={f.at} onChange={(e) => setF({ ...f, at: e.target.value })} /></Field>
            <Field label="สถานที่"><input className={inputCls} value={f.place} onChange={(e) => setF({ ...f, place: e.target.value })} /></Field>
            <Field label="เหตุผลในการนัด"><input className={inputCls} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
          </div>
          <div className="mt-6 flex justify-end"><Btn onClick={save}>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
        </Modal>
      )}
    </>
  )
}
