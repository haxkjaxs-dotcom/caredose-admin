import { useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Field, H, Modal, Search, Table, inputCls } from '../ui'
import type { Ctx } from '../ctx'

type Med = {
  id: string; generic_name: string; trade_name: string | null; form: string | null; strength: string | null
  unit: string | null; usage: string | null; warning: string | null; stock: number; is_active: boolean
}
const blank = { generic_name: '', trade_name: '', form: 'เม็ด', strength: '', unit: 'มก.', usage: '', warning: '', stock: '0' }
const nul = (s: string) => s.trim() || null

export function Meds({ notify }: Ctx) {
  const [meds, setMeds] = useState<Med[]>([])
  const [q, setQ] = useState('')
  const [form, setForm] = useState(false)
  const [f, setF] = useState(blank)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  const load = async () => {
    const { data, error } = await supabase.from('medicines').select('*').order('generic_name')
    if (error) return notify('โหลดคลังยาไม่สำเร็จ: ' + error.message)
    setMeds(data ?? [])
  }
  useEffect(() => { load() }, [])

  const add = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    const stock = Number(f.stock)
    if (!f.generic_name.trim()) return setErr('กรุณาระบุชื่อสามัญ')
    if (!Number.isInteger(stock) || stock < 0) return setErr('จำนวนคงเหลือต้องเป็นจำนวนเต็ม 0 ขึ้นไป')
    setBusy(true)
    setErr('')
    const { error } = await supabase.from('medicines').insert({
      generic_name: f.generic_name.trim(), trade_name: nul(f.trade_name), form: nul(f.form), strength: nul(f.strength),
      unit: nul(f.unit), usage: nul(f.usage), warning: nul(f.warning), stock,
    })
    setBusy(false)
    if (error) return setErr('บันทึกไม่สำเร็จ: ' + error.message)
    setForm(false)
    setF(blank)
    notify('เพิ่มยาแล้ว')
    load()
  }

  const toggle = async (m: Med) => {
    const { error } = await supabase.from('medicines').update({ is_active: !m.is_active }).eq('id', m.id)
    if (error) return notify('เปลี่ยนสถานะไม่สำเร็จ: ' + error.message)
    load()
  }

  const rows = meds.filter((m) => (m.generic_name + (m.trade_name ?? '')).toLowerCase().includes(q.toLowerCase()))
  return (
    <>
      <Card>
        <H action={<Btn onClick={() => setForm(true)}>เพิ่มยา</Btn>}>คลังยาสถานพยาบาล</H>
        <div className="mb-4"><Search v={q} set={setQ} ph="ค้นหาชื่อยา" /></div>
        <Table
          head={['ชื่อสามัญ', 'ชื่อการค้า', 'รูปแบบ', 'ขนาด', 'วิธีใช้', 'คำเตือน', 'คงเหลือ', '']}
          rows={rows.map((m) => [<b>{m.generic_name}</b>, m.trade_name ?? '-', m.form ?? '-', [m.strength, m.unit].filter(Boolean).join(' ') || '-', m.usage ?? '-', m.warning ?? '-',
            m.is_active ? <Badge tone={m.stock < 30 ? 'yellow' : 'green'}>{m.stock}{m.stock < 30 ? ' (ใกล้หมด)' : ''}</Badge> : <Badge tone="gray">ปิดใช้งาน</Badge>,
            <Btn kind="ghost" onClick={() => toggle(m)}>{m.is_active ? 'ปิดใช้งาน' : 'เปิดใช้งาน'}</Btn>])}
        />
      </Card>
      {form && (
        <Modal title="เพิ่มยา" onClose={() => setForm(false)}>
          <form onSubmit={add} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="ชื่อสามัญ *"><input className={inputCls} value={f.generic_name} onChange={(e) => setF({ ...f, generic_name: e.target.value })} /></Field>
              <Field label="ชื่อการค้า"><input className={inputCls} value={f.trade_name} onChange={(e) => setF({ ...f, trade_name: e.target.value })} /></Field>
              <Field label="รูปแบบ">
                <select className={inputCls} value={f.form} onChange={(e) => setF({ ...f, form: e.target.value })}>
                  {['เม็ด', 'แคปซูล', 'น้ำ', 'ฉีด', 'ครีม/ขี้ผึ้ง', 'อื่น ๆ'].map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
              <Field label="จำนวนคงเหลือ"><input className={inputCls} type="number" min={0} step={1} value={f.stock} onChange={(e) => setF({ ...f, stock: e.target.value })} /></Field>
              <Field label="ความแรง (เช่น 500)"><input className={inputCls} value={f.strength} onChange={(e) => setF({ ...f, strength: e.target.value })} /></Field>
              <Field label="หน่วย (เช่น มก.)"><input className={inputCls} value={f.unit} onChange={(e) => setF({ ...f, unit: e.target.value })} /></Field>
            </div>
            <Field label="วิธีใช้"><input className={inputCls} value={f.usage} onChange={(e) => setF({ ...f, usage: e.target.value })} /></Field>
            <Field label="คำเตือน"><input className={inputCls} value={f.warning} onChange={(e) => setF({ ...f, warning: e.target.value })} /></Field>
            {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
            <div className="flex justify-end"><Btn>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
          </form>
        </Modal>
      )}
    </>
  )
}
