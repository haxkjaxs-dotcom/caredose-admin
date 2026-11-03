import { useState } from 'react'
import * as D from '../data'
import { Btn, Card, Field, Modal, Select, Table, inputCls, mName, pName } from '../ui'
import type { Ctx } from '../ctx'

export function Plans({ patients, plans, setPlans, notify, ids }: Ctx) {
  const [pid, setPid] = useState(''); const [view, setView] = useState<'day' | 'week'>('day'); const [form, setForm] = useState(false)
  const list = plans.filter((r) => ids.has(r.patient) && (!pid || r.patient === pid))
  const [f, setF] = useState({ patient: patients[0]?.id ?? '', med: 'm1', dose: '', qty: '1 เม็ด', time: 'เช้า', start: '2025-06-12', end: '2025-12-31', advice: 'หลังอาหาร', note: '' })
  const save = () => {
    if (!f.patient) return notify('ยังไม่มีผู้ป่วยในระบบ')
    setPlans([...plans, { id: 'r' + Date.now(), patient: f.patient, med: f.med, dose: f.dose || '-', qty: f.qty, times: [f.time], start: f.start, end: f.end, advice: f.advice, note: f.note }])
    setForm(false); notify('บันทึกแผนยาแล้ว และส่งแจ้งเตือนไปยังผู้ป่วย/ผู้ดูแล')
  }
  const slots = ['เช้า', 'กลางวัน', 'เย็น', 'ก่อนนอน']
  return (
    <>
      <Card>
        <div className="mb-4 flex flex-col gap-3 sm:flex-row">
          <Select v={pid} set={setPid} all="ผู้ป่วยทั้งหมด" opts={patients.map((p) => [p.id, p.name])} />
          <Select v={view} set={(v) => setView((v || 'day') as 'day')} all="ตารางรายวัน" opts={[['week', 'ตารางรายสัปดาห์']]} />
          <div className="sm:ml-auto"><Btn onClick={() => setForm(true)}>เพิ่มแผนยา</Btn></div>
        </div>
        {view === 'day' ? (
          <Table
            head={['ผู้ป่วย', 'ยา', 'ขนาด/จำนวน', 'มื้อ', 'ช่วงเวลา', 'คำแนะนำ', 'หมายเหตุแพทย์', '']}
            rows={list.map((r) => [pName(r.patient), mName(r.med), `${r.dose} × ${r.qty}`, r.times.join(', '), `${r.start} – ${r.end}`, r.advice, r.note || '-',
              <Btn kind="danger" onClick={() => { setPlans(plans.filter((x) => x.id !== r.id)); notify('ยกเลิกแผนยาแล้ว') }}>ยกเลิก</Btn>])}
          />
        ) : (
          <Table
            head={['มื้อ', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.']}
            rows={slots.map((s) => [<b>{s}</b>, ...Array.from({ length: 7 }, () => <span className="text-sm">{list.filter((r) => r.times.includes(s)).map((r) => mName(r.med)).join(', ') || '-'}</span>)])}
          />
        )}
      </Card>
      {form && (
        <Modal title="เพิ่มแผนยา" onClose={() => setForm(false)}>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="ผู้ป่วย"><select className={inputCls} value={f.patient} onChange={(e) => setF({ ...f, patient: e.target.value })}>{patients.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></Field>
            <Field label="ยา"><select className={inputCls} value={f.med} onChange={(e) => setF({ ...f, med: e.target.value })}>{D.medicines.filter((m) => m.active).map((m) => <option key={m.id} value={m.id}>{m.generic}</option>)}</select></Field>
            <Field label="ขนาดยา"><input className={inputCls} value={f.dose} onChange={(e) => setF({ ...f, dose: e.target.value })} placeholder="เช่น 500 มก." /></Field>
            <Field label="จำนวนที่ต้องทาน"><input className={inputCls} value={f.qty} onChange={(e) => setF({ ...f, qty: e.target.value })} /></Field>
            <Field label="มื้อยา"><select className={inputCls} value={f.time} onChange={(e) => setF({ ...f, time: e.target.value })}>{slots.map((s) => <option key={s}>{s}</option>)}</select></Field>
            <Field label="คำแนะนำ"><select className={inputCls} value={f.advice} onChange={(e) => setF({ ...f, advice: e.target.value })}><option>ก่อนอาหาร</option><option>หลังอาหาร</option></select></Field>
            <Field label="วันที่เริ่ม"><input type="date" className={inputCls} value={f.start} onChange={(e) => setF({ ...f, start: e.target.value })} /></Field>
            <Field label="วันที่สิ้นสุด"><input type="date" className={inputCls} value={f.end} onChange={(e) => setF({ ...f, end: e.target.value })} /></Field>
          </div>
          <div className="mt-4"><Field label="หมายเหตุจากแพทย์"><input className={inputCls} value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} /></Field></div>
          <div className="mt-6 flex justify-end"><Btn onClick={save}>บันทึก</Btn></div>
        </Modal>
      )}
    </>
  )
}
