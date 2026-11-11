import { useState } from 'react'
import * as D from '../data'
import type { Appt } from '../data'
import { Badge, Btn, Card, Field, Modal, Select, Table, apTone, dName, fmt, inputCls, pName } from '../ui'
import type { Ctx } from '../ctx'

export function Appts({ patients, appts, setAppts, notify, ids, openPatient }: Ctx) {
  const all = appts
  const [form, setForm] = useState(false); const [st, setSt] = useState('')
  const [q, setQ] = useState(''); const [pid, setPid] = useState('')
  const [f, setF] = useState({ doctor: 'd1', at: '2025-06-20T09:00', place: '', reason: '', note: '' })
  const sugg = q && !pid ? patients.filter((p) => p.name.includes(q)) : []
  const set = (id: string, status: Appt['status']) => { setAppts(appts.map((a) => (a.id === id ? { ...a, status } : a))); notify(`อัปเดตสถานะเป็น "${status}"`) }
  const save = () => {
    if (!pid) return notify('กรุณาเลือกผู้ป่วยจากรายการ')
    setAppts([...appts, { id: 'a' + Date.now(), patient: pid, status: 'รอนัด', ...f }]); setForm(false); setQ(''); setPid(''); notify('สร้างนัดหมายแล้ว จะแจ้งเตือนล่วงหน้า 1 วัน')
  }
  void ids
  return (
    <>
      <Card>
        <div className="mb-4 flex gap-3">
          <Select v={st} set={setSt} all="ทุกสถานะ" opts={['รอนัด', 'มาตามนัด', 'เลื่อนนัด', 'ยกเลิก'].map((s) => [s, s])} />
          <div className="ml-auto"><Btn onClick={() => setForm(true)}>เพิ่มนัดหมาย</Btn></div>
        </div>
        <Table
          head={['ผู้ป่วย', 'ผู้ดูแลภาพรวม', 'วันที่และเวลา', 'สถานที่', 'เหตุผล', 'สถานะ', 'จัดการ']}
          rows={all.filter((a) => !st || a.status === st).sort((a, b) => a.at.localeCompare(b.at)).map((a) => [
            <button className="font-semibold text-brand-700 hover:underline" onClick={() => openPatient(a.patient)}>{pName(a.patient)}</button>,
            dName(a.doctor), fmt(a.at), a.place, a.reason, <Badge tone={apTone[a.status]}>{a.status}</Badge>,
            <div className="flex flex-wrap gap-2">
              <Btn kind="ghost" onClick={() => openPatient(a.patient)}>ดูประวัติการทานยา</Btn>
              <Btn kind="ghost" onClick={() => set(a.id, 'เลื่อนนัด')}>เลื่อน</Btn>
              <Btn kind="danger" onClick={() => set(a.id, 'ยกเลิก')}>ยกเลิก</Btn>
            </div>,
          ])}
        />
      </Card>
      {form && (
        <Modal title="เพิ่มนัดหมาย" onClose={() => setForm(false)}>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="relative sm:col-span-2">
              <Field label="ผู้ป่วย (พิมพ์เพื่อค้นหา)"><input className={inputCls} value={q} onChange={(e) => { setQ(e.target.value); setPid('') }} /></Field>
              {sugg.length > 0 && (
                <ul className="absolute z-10 mt-1 w-full overflow-hidden rounded-xl border border-slate-200 bg-white shadow-lg">
                  {sugg.map((p) => <li key={p.id}><button className="min-h-11 w-full px-3 text-left hover:bg-brand-50" onClick={() => { setPid(p.id); setQ(p.name) }}>{p.name}</button></li>)}
                </ul>
              )}
            </div>
            <Field label="ผู้ดูแลภาพรวม"><select className={inputCls} value={f.doctor} onChange={(e) => setF({ ...f, doctor: e.target.value })}>{D.doctors.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></Field>
            <Field label="วันที่และเวลา"><input type="datetime-local" className={inputCls} value={f.at} onChange={(e) => setF({ ...f, at: e.target.value })} /></Field>
            <Field label="สถานที่"><input className={inputCls} value={f.place} onChange={(e) => setF({ ...f, place: e.target.value })} /></Field>
            <Field label="เหตุผลในการนัด"><input className={inputCls} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
          </div>
          <div className="mt-6 flex justify-end"><Btn onClick={save}>บันทึก</Btn></div>
        </Modal>
      )}
    </>
  )
}
