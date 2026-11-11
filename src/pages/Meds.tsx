import { useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Field, H, Modal, Search, Table, inputCls } from '../ui'
import type { Ctx } from '../ctx'

type Med = {
  id: string; generic_name: string; trade_name: string | null; form: string | null; strength: string | null
  unit: string | null; usage: string | null; warning: string | null; stock: number; is_active: boolean
}
const blank = { generic_name: '', form: 'เม็ด', strength: '', unit: 'มก.', usage: '', warning: '', stock: '0' }
const nul = (s: string) => s.trim() || null

export function Meds({ notify, role }: Ctx) {
  const [meds, setMeds] = useState<Med[]>([])
  const [q, setQ] = useState('')
  const [form, setForm] = useState(false)
  const [f, setF] = useState(blank)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const [restock, setRestock] = useState<Med | null>(null)
  const [qty, setQty] = useState('')

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
      generic_name: f.generic_name.trim(), form: nul(f.form), strength: nul(f.strength),
      unit: nul(f.unit), usage: nul(f.usage), warning: nul(f.warning), stock,
    })
    setBusy(false)
    if (error) return setErr('บันทึกไม่สำเร็จ: ' + error.message)
    setForm(false)
    setF(blank)
    notify('เพิ่มยาแล้ว')
    load()
  }

  const addStock = async (e: FormEvent) => {
    e.preventDefault()
    if (busy || !restock) return
    const n = Number(qty)
    if (!Number.isInteger(n) || n < 1) return setErr('จำนวนที่รับเข้าต้องเป็นจำนวนเต็ม 1 ขึ้นไป')
    setBusy(true)
    setErr('')
    // .eq('stock', ...) makes this a compare-and-set: if someone else changed the stock meanwhile, 0 rows match and nothing is lost
    const { data, error } = await supabase.from('medicines').update({ stock: restock.stock + n }).eq('id', restock.id).eq('stock', restock.stock).select('id')
    setBusy(false)
    if (error) return setErr('บันทึกไม่สำเร็จ: ' + error.message)
    if (!data?.length) {
      setRestock(null)
      load()
      return notify('จำนวนคงเหลือเพิ่งถูกเปลี่ยนโดยผู้อื่น ตรวจสอบตัวเลขใหม่แล้วลองอีกครั้ง')
    }
    setRestock(null)
    notify(`รับยาเข้า ${n} ${restock.unit ?? ''} แล้ว คงเหลือ ${restock.stock + n}`)
    load()
  }

  const toggle = async (m: Med) => {
    const { error } = await supabase.from('medicines').update({ is_active: !m.is_active }).eq('id', m.id)
    if (error) return notify('เปลี่ยนสถานะไม่สำเร็จ: ' + error.message)
    load()
  }

  const remove = async (m: Med) => {
    if (!window.confirm(`ลบยา "${m.generic_name}" ถาวร?`)) return
    // select() so a delete that RLS silently filtered out (0 rows) is reported, not shown as success
    const { data, error } = await supabase.from('medicines').delete().eq('id', m.id).select('id')
    if (error) return notify(error.code === '23503' ? 'ลบไม่ได้: ยานี้ถูกใช้ในแผนการใช้ยาแล้ว ให้ปิดใช้งานแทน' : 'ลบยาไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('ลบยาไม่สำเร็จ: ไม่มีสิทธิ์')
    notify('ลบยาแล้ว')
    load()
  }

  const rows = meds.filter((m) => m.generic_name.toLowerCase().includes(q.toLowerCase()))
  return (
    <>
      <Card>
        <H action={<Btn onClick={() => setForm(true)}>เพิ่มยา</Btn>}>คลังยาสถานพยาบาล</H>
        <div className="mb-4"><Search v={q} set={setQ} ph="ค้นหาชื่อยา" /></div>
        <Table
          head={['ชื่อสามัญ', 'รูปแบบ', 'ปริมาณตัวยา', 'วิธีใช้', 'คำเตือน', 'คงเหลือ', '']}
          rows={rows.map((m) => [<b>{m.generic_name}</b>, m.form ?? '-', [m.strength, m.unit].filter(Boolean).join(' ') || '-', m.usage ?? '-', m.warning ?? '-',
            m.is_active ? <Badge tone={m.stock < 30 ? 'yellow' : 'green'}>{m.stock}{m.stock < 30 ? ' (ใกล้หมด)' : ''}</Badge> : <Badge tone="gray">ปิดใช้งาน</Badge>,
            <div className="flex gap-2">
              <Btn kind="ghost" onClick={() => { setErr(''); setQty(''); setRestock(m) }}>รับยาเข้า</Btn>
              <Btn kind="ghost" onClick={() => toggle(m)}>{m.is_active ? 'ปิดใช้งาน' : 'เปิดใช้งาน'}</Btn>
              {role === 'Admin' && <Btn kind="danger" onClick={() => remove(m)}>ลบ</Btn>}{/* cosmetic: med_d decides */}
            </div>])}
        />
      </Card>
      {restock && (
        <Modal title={`รับยาเข้า: ${restock.generic_name}`} onClose={() => setRestock(null)}>
          <form onSubmit={addStock} className="space-y-4">
            <div className="text-slate-600">คงเหลือปัจจุบัน <b>{restock.stock}</b></div>
            <Field label="จำนวนที่รับเข้า (บวกเพิ่มจากคงเหลือ) *"><input className={inputCls} type="number" min={1} step={1} autoFocus value={qty} onChange={(e) => setQty(e.target.value)} /></Field>
            {Number(qty) >= 1 && <div className="text-slate-600">คงเหลือใหม่ <b>{restock.stock + Math.floor(Number(qty))}</b></div>}
            {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
            <div className="flex justify-end"><Btn>{busy ? 'กำลังบันทึก...' : 'บันทึก'}</Btn></div>
          </form>
        </Modal>
      )}
      {form && (
        <Modal title="เพิ่มยา" onClose={() => setForm(false)}>
          <form onSubmit={add} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="ชื่อสามัญ *"><input className={inputCls} value={f.generic_name} onChange={(e) => setF({ ...f, generic_name: e.target.value })} /></Field>
              <Field label="รูปแบบ">
                <select className={inputCls} value={f.form} onChange={(e) => setF({ ...f, form: e.target.value })}>
                  {['เม็ด', 'แคปซูล', 'น้ำ', 'ฉีด', 'ครีม/ขี้ผึ้ง', 'อื่น ๆ'].map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
              <Field label="จำนวนคงเหลือ"><input className={inputCls} type="number" min={0} step={1} value={f.stock} onChange={(e) => setF({ ...f, stock: e.target.value })} /></Field>
              <Field label="ปริมาณตัวยา (เช่น 500)"><input className={inputCls} inputMode="decimal" placeholder="ตัวเลขบนฉลาก เช่น 500" value={f.strength} onChange={(e) => setF({ ...f, strength: e.target.value })} /></Field>
              <Field label="หน่วยของปริมาณตัวยา">
                <select className={inputCls} value={f.unit} onChange={(e) => setF({ ...f, unit: e.target.value })}>
                  {['มก.', 'กรัม', 'มคก.', 'มล.', 'หน่วย'].map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
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
