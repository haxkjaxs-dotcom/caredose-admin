import { useEffect, useRef, useState, type FormEvent } from 'react'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Field, H, Modal, Select, Table, inputCls } from '../ui'
import { normalizeTimes, planRowToView, planRpcArgs, planToForm, validatePlanForm, type PlanForm as Form, type PlanRow, type PlanView } from '../lib/plans'
import type { Ctx } from '../ctx'
import { canEditPlans } from '../lib/roles'

type Patient = { id: string; full_name: string }
type Med = { id: string; generic_name: string; trade_name: string | null; is_active: boolean }

const today = () => new Date().toLocaleDateString('en-CA')
const blank = (): Form => ({ id: null, medicineId: '', dose: '', meal: '', start: today(), end: '', note: '', times: ['08:00'], status: 'active' })

// every write goes through the save_plan RPC: the database checks permission, the UI only hides buttons
const savePlan = (patientId: string, f: Form, times: string[], status?: string) =>
  supabase.rpc('save_plan', planRpcArgs(patientId, f, times, status))

const ErrBox = ({ children }: { children: string }) => <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{children}</div>
const Hint = ({ children }: { children: string }) => <p className="py-8 text-center text-slate-400">{children}</p>

export function Plans({ notify, role }: Ctx) {
  const [patients, setPatients] = useState<Patient[]>([])
  const [meds, setMeds] = useState<Med[]>([])
  const [pid, setPid] = useState('')
  const [plans, setPlans] = useState<PlanView[] | null>(null)
  const [loadErr, setLoadErr] = useState('')
  const [form, setForm] = useState<Form | null>(null)
  const cur = useRef('') // drops answers that arrive after the user picked another patient
  const canEdit = canEditPlans(role) // cosmetic: the database decides

  useEffect(() => {
    supabase.from('patients').select('id, full_name').order('full_name').then(({ data, error }) => {
      if (error) return notify('โหลดรายชื่อผู้ป่วยไม่สำเร็จ: ' + error.message)
      setPatients(data ?? [])
    })
    if (!canEdit) return // the medicine list is only for the plan form
    supabase.from('medicines').select('id, generic_name, trade_name, is_active').order('generic_name').then(({ data, error }) => {
      if (error) return notify('โหลดคลังยาไม่สำเร็จ: ' + error.message)
      setMeds(data ?? [])
    })
  }, [])

  const load = async (id: string) => {
    setLoadErr('')
    const { data, error } = await supabase.from('medication_plans')
      .select('id, medicine_id, dose, meal_relation, start_date, end_date, status, doctor_note, medicines(generic_name, trade_name), medication_schedules(time_of_day)')
      .eq('patient_id', id).order('start_date', { ascending: false })
    if (cur.current !== id) return
    if (error) return setLoadErr('โหลดแผนยาไม่สำเร็จ: ' + error.message)
    setPlans((data as unknown as PlanRow[]).map(planRowToView))
  }
  useEffect(() => {
    cur.current = pid
    setPlans(null)
    if (pid) load(pid)
  }, [pid])

  const stop = async (v: PlanView) => {
    if (!confirm(`หยุดแผนยา ${v.name}?`)) return
    const { error } = await savePlan(pid, planToForm(v), v.times, 'stopped')
    if (error) return notify(error.message)
    notify('หยุดแผนยาแล้ว')
    load(pid)
  }

  return (
    <>
      <Card>
        <H action={canEdit && pid ? <Btn onClick={() => setForm(blank())}>เพิ่มแผนยา</Btn> : undefined}>แผนยา</H>
        <div className="mb-4"><Select v={pid} set={setPid} all="เลือกผู้ป่วย" opts={patients.map((p) => [p.id, p.full_name])} /></div>
        {!pid ? <Hint>เลือกผู้ป่วยเพื่อดูแผนยา</Hint>
          : loadErr ? <ErrBox>{loadErr}</ErrBox>
          : !plans ? <Hint>กำลังโหลด...</Hint>
          : (
            <Table
              head={['ยา', 'ขนาด', 'มื้อ', 'ช่วงวัน', 'เวลา', 'สถานะ', '']}
              rows={plans.map((v) => [<b>{v.name}</b>, v.dose, v.meal || '-', v.range, v.times.join(', ') || '-',
                <Badge tone={v.status === 'active' ? 'green' : 'gray'}>{v.statusLabel}</Badge>,
                canEdit ? <div className="flex gap-2"><Btn kind="ghost" onClick={() => setForm(planToForm(v))}>แก้ไข</Btn>{v.status === 'active' && <Btn kind="danger" onClick={() => stop(v)}>หยุดแผน</Btn>}</div> : ''])}
            />
          )}
      </Card>
      {form && <PlanForm init={form} pid={pid} meds={meds} notify={notify} onClose={() => setForm(null)} onSaved={() => { setForm(null); load(pid) }} />}
    </>
  )
}

function PlanForm({ init, pid, meds, notify, onClose, onSaved }: { init: Form; pid: string; meds: Med[]; notify: (m: string) => void; onClose: () => void; onSaved: () => void }) {
  const [f, setF] = useState(init)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const set = (k: keyof Form) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  const setTime = (i: number, v: string) => setF({ ...f, times: f.times.map((t, j) => (j === i ? v : t)) })

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    const times = normalizeTimes(f.times)
    const bad = validatePlanForm({ medicineId: f.medicineId, dose: f.dose, start: f.start, end: f.end, times })
    if (bad) return setErr(bad)
    setBusy(true)
    setErr('')
    const { error } = await savePlan(pid, f, times)
    setBusy(false)
    if (error) return setErr(error.message)
    notify(f.id ? 'แก้ไขแผนยาแล้ว' : 'เพิ่มแผนยาแล้ว')
    onSaved()
  }

  return (
    <Modal title={f.id ? 'แก้ไขแผนยา' : 'เพิ่มแผนยา'} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="ยา *">
            <select className={inputCls} value={f.medicineId} onChange={set('medicineId')}>
              <option value="">เลือกยา</option>
              {meds.filter((m) => m.is_active || m.id === init.medicineId).map((m) => <option key={m.id} value={m.id}>{m.trade_name || m.generic_name}{m.is_active ? '' : ' (ปิดใช้งาน)'}</option>)}
            </select>
          </Field>
          <Field label="ขนาดยา *"><input className={inputCls} value={f.dose} onChange={set('dose')} placeholder="เช่น 1 เม็ด" maxLength={100} /></Field>
          <Field label="ความสัมพันธ์กับมื้ออาหาร">
            <input className={inputCls} list="meal-options" value={f.meal} onChange={set('meal')} maxLength={50} />
            <datalist id="meal-options"><option value="ก่อนอาหาร" /><option value="หลังอาหาร" /><option value="พร้อมอาหาร" /></datalist>
          </Field>
          <Field label="วันที่เริ่ม *"><input type="date" className={inputCls} value={f.start} onChange={set('start')} /></Field>
          <Field label="วันที่สิ้นสุด (ไม่บังคับ)"><input type="date" className={inputCls} value={f.end} onChange={set('end')} /></Field>
        </div>
        <Field label="หมายเหตุจากแพทย์"><input className={inputCls} value={f.note} onChange={set('note')} maxLength={500} /></Field>
        <div>
          <div className="mb-1 text-sm font-medium text-slate-600">เวลาทานยา *</div>
          <div className="space-y-2">
            {f.times.map((t, i) => (
              <div key={i} className="flex gap-2">
                <input type="time" aria-label={`เวลาที่ ${i + 1}`} className={inputCls} value={t} onChange={(e) => setTime(i, e.target.value)} />
                {f.times.length > 1 && <Btn kind="ghost" onClick={() => setF({ ...f, times: f.times.filter((_, j) => j !== i) })}>ลบ</Btn>}
              </div>
            ))}
          </div>
          <div className="mt-2"><Btn kind="ghost" onClick={() => setF({ ...f, times: [...f.times, ''] })}>เพิ่มเวลา</Btn></div>
        </div>
        {err && <ErrBox>{err}</ErrBox>}
        <div className="flex justify-end"><Btn disabled={busy}>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
      </form>
    </Modal>
  )
}
