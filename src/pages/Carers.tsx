import { useEffect, useState, type FormEvent } from 'react'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Field, H, Modal, Table, inputCls } from '../ui'
import { normalizePhoneDigits } from '../lib/plans'
import type { Ctx } from '../ctx'

type Link = { patient_id: string; relationship: string | null; can_manage_plan: boolean; patients: { full_name: string } | null }
type Carer = { id: string; full_name: string; phone: string | null; patient_caregivers: Link[] }
type Pat = { id: string; full_name: string }
const blank = { name: '', phone: '', pin: '', patient: '', rel: '', manage: false }
const nul = (s: string) => s.trim() || null

export function Carers({ notify, role }: Ctx) {
  const [carers, setCarers] = useState<Carer[]>([])
  const [pats, setPats] = useState<Pat[]>([])
  const [form, setForm] = useState<string | 'new' | null>(null) // caregiver id being edited, or 'new'
  const [f, setF] = useState(blank)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const canEdit = role === 'Admin' || role === 'Doctor' // cosmetic: cg_w / cg_u_doctor / pc_* decide; deleting a caregiver is Admin only

  const load = async () => {
    const [c, p] = await Promise.all([
      supabase.from('caregivers').select('id, full_name, phone, patient_caregivers(patient_id, relationship, can_manage_plan, patients(full_name))').order('full_name'),
      supabase.from('patients').select('id, full_name').order('full_name'),
    ])
    const bad = c.error ?? p.error
    if (bad) return notify('โหลดข้อมูลญาติไม่สำเร็จ: ' + bad.message)
    setCarers((c.data ?? []) as unknown as Carer[])
    setPats(p.data ?? [])
  }
  useEffect(() => { load() }, [])

  const open = (c?: Carer) => {
    setErr('')
    setF(c ? { ...blank, name: c.full_name, phone: c.phone ?? '' } : blank)
    setForm(c?.id ?? 'new')
  }
  // picking a patient the caregiver is already linked to loads that link, so it can be edited
  const pick = (patient: string) => {
    const l = carers.find((c) => c.id === form)?.patient_caregivers.find((x) => x.patient_id === patient)
    setF({ ...f, patient, rel: l?.relationship ?? '', manage: l?.can_manage_plan ?? false })
  }

  const save = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    if (!f.name.trim()) return setErr('กรุณาระบุชื่อ-นามสกุล')
    if (form === 'new' && !/^\d{9,10}$/.test(normalizePhoneDigits(f.phone))) return setErr('กรุณากรอกเบอร์โทร 9-10 หลัก (ใช้เป็นชื่อผู้ใช้)')
    if (form === 'new' && !/^\d{6}$/.test(f.pin)) return setErr('กรุณากำหนด PIN 6 หลัก')
    setBusy(true)
    setErr('')
    const row = { full_name: f.name.trim(), phone: nul(f.phone) }
    let r
    if (form === 'new') {
      // a new caregiver is also a user account (phone + PIN, role caregiver); create-user makes the caregivers row and links it
      const acc = await supabase.functions.invoke('create-user', { body: { username: normalizePhoneDigits(f.phone), full_name: row.full_name, pin: f.pin, role: 'caregiver' } })
      if (acc.error) {
        const body = acc.error instanceof FunctionsHttpError ? await acc.error.context.json().catch(() => null) : null
        setBusy(false)
        return setErr('สร้างบัญชีไม่สำเร็จ: ' + (body?.error ?? acc.error.message))
      }
      r = await supabase.from('caregivers').select('id').eq('user_id', acc.data.id).maybeSingle()
      // an older deployed create-user does not make the caregivers row: make it here so the list always gets it
      if (!r.error && !r.data) r = await supabase.from('caregivers').insert({ user_id: acc.data.id, ...row }).select('id').single()
    } else {
      r = await supabase.from('caregivers').update(row).eq('id', form!).select('id').single()
    }
    if (r.error || !r.data) {
      setBusy(false)
      load()
      return setErr('บันทึกไม่สำเร็จ: ' + (r.error?.message ?? 'ไม่มีสิทธิ์'))
    }
    if (f.patient) {
      const l = await supabase.from('patient_caregivers').upsert(
        { patient_id: f.patient, caregiver_id: r.data.id, relationship: nul(f.rel), can_manage_plan: f.manage },
        { onConflict: 'patient_id,caregiver_id' },
      )
      if (l.error) {
        setBusy(false)
        load()
        return setErr('บันทึกญาติแล้ว แต่ผูกกับผู้ป่วยไม่สำเร็จ: ' + l.error.message)
      }
    }
    setBusy(false)
    setForm(null)
    notify(form === 'new' ? 'เพิ่มญาติ/ผู้ดูแลแล้ว' : 'บันทึกแล้ว')
    load()
  }

  // select() so a delete that RLS silently filtered out (0 rows) is reported, not shown as success
  const remove = async (c: Carer) => {
    if (!window.confirm(`ลบ "${c.full_name}" ถาวร? การผูกกับผู้ป่วยจะถูกลบด้วย`)) return
    const { data, error } = await supabase.from('caregivers').delete().eq('id', c.id).select('id')
    if (error) return notify('ลบไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('ลบไม่สำเร็จ: ไม่มีสิทธิ์')
    notify('ลบแล้ว')
    load()
  }
  const unlink = async (c: Carer, l: Link) => {
    if (!window.confirm(`เลิกผูก "${c.full_name}" กับ "${l.patients?.full_name ?? '-'}"?`)) return
    const { data, error } = await supabase.from('patient_caregivers').delete().eq('caregiver_id', c.id).eq('patient_id', l.patient_id).select('patient_id')
    if (error) return notify('เลิกผูกไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('เลิกผูกไม่สำเร็จ: ไม่มีสิทธิ์')
    notify('เลิกผูกแล้ว')
    if (f.patient === l.patient_id) setF({ ...f, patient: '', rel: '', manage: false })
    load()
  }
  const editing = carers.find((c) => c.id === form)

  return (
    <>
      <Card>
        <H action={canEdit && <Btn onClick={() => open()}>เพิ่มญาติ/ผู้ดูแล</Btn>}>ญาติและผู้ดูแล</H>
        <Table
          head={['ชื่อ-นามสกุล', 'เบอร์โทร', 'ผู้ป่วยที่ดูแล', 'สิทธิ์', '']}
          rows={carers.map((c) => [
            <b>{c.full_name}</b>, c.phone ?? '-',
            c.patient_caregivers.map((l) => (l.patients?.full_name ?? '-') + (l.relationship ? ` (${l.relationship})` : '')).join(', ') || '-',
            <Badge tone={c.patient_caregivers.some((l) => l.can_manage_plan) ? 'green' : 'gray'}>{c.patient_caregivers.some((l) => l.can_manage_plan) ? 'จัดการแผนยาได้' : 'ดูอย่างเดียว'}</Badge>,
            canEdit ? <div className="flex gap-2"><Btn kind="ghost" onClick={() => open(c)}>แก้ไข</Btn>{role === 'Admin' && <Btn kind="danger" onClick={() => remove(c)}>ลบ</Btn>}</div> : '',
          ])}
        />
      </Card>
      {form && (
        <Modal title={form === 'new' ? 'เพิ่มญาติ/ผู้ดูแล' : 'แก้ไขญาติ/ผู้ดูแล'} onClose={() => setForm(null)}>
          <form onSubmit={save} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="ชื่อ-นามสกุล *"><input className={inputCls} value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
              <Field label={form === 'new' ? 'เบอร์โทร * (ใช้เป็นชื่อผู้ใช้)' : 'เบอร์โทร'}><input className={inputCls} inputMode="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} /></Field>
              {form === 'new' && <Field label="PIN 6 หลัก *"><input className={inputCls} inputMode="numeric" maxLength={6} value={f.pin} onChange={(e) => setF({ ...f, pin: e.target.value.replace(/\D/g, '') })} /></Field>}
            </div>
            {!!editing?.patient_caregivers.length && (
              <ul className="space-y-2">
                {editing.patient_caregivers.map((l) => (
                  <li key={l.patient_id} className="flex items-center justify-between gap-2 rounded-xl bg-slate-50 px-3 py-2">
                    <span>{l.patients?.full_name ?? '-'}{l.relationship ? ` (${l.relationship})` : ''}</span>
                    <Btn kind="danger" onClick={() => unlink(editing, l)}>เลิกผูก</Btn>
                  </li>
                ))}
              </ul>
            )}
            <Field label="ผู้ป่วยที่ดูแล (เลือกเพื่อผูกหรือแก้ไขความสัมพันธ์)">
              <select className={inputCls} value={f.patient} onChange={(e) => pick(e.target.value)}>
                <option value="">- ไม่ผูกผู้ป่วย -</option>
                {pats.map((p) => <option key={p.id} value={p.id}>{p.full_name}</option>)}
              </select>
            </Field>
            {f.patient && (
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="ความสัมพันธ์"><input className={inputCls} value={f.rel} onChange={(e) => setF({ ...f, rel: e.target.value })} /></Field>
                <label className="flex min-h-11 items-center gap-2 self-end"><input type="checkbox" checked={f.manage} onChange={(e) => setF({ ...f, manage: e.target.checked })} />จัดการแผนยาได้</label>
              </div>
            )}
            {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
            <div className="flex justify-end"><Btn>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
          </form>
        </Modal>
      )}
    </>
  )
}
