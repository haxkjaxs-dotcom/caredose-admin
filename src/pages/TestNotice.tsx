import { useState } from 'react'
import { supabase } from '../supabase'
import { Btn, Card, H, Modal } from '../ui'
import type { Ctx } from '../ctx'

const KINDS = [
  { id: 'before', title: '1. เตือนก่อนทานยา', hint: 'ข้อความ "ใกล้ถึงเวลาทานยา" ที่ผู้ป่วยได้รับก่อนถึงเวลา' },
  { id: 'now', title: '2. เตือนตอนทานยา', hint: 'ข้อความ "ถึงเวลาทานยาแล้ว" ที่ผู้ป่วยได้รับตอนถึงเวลา' },
  { id: 'missed', title: '3. เตือนหลังไม่ได้ทานยา', hint: 'ข้อความ "ยังไม่ได้ทานยา" ที่ผู้ป่วยได้รับหลังเลยเวลา' },
]

// the database (send_test_notification) is the permission gate; the menu entry is Admin only
export function TestNotice({ notify }: Ctx) {
  const [kind, setKind] = useState<(typeof KINDS)[number] | null>(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const send = async () => {
    if (busy || !kind) return
    setBusy(true)
    setErr('')
    const { data, error } = await supabase.rpc('send_test_notification', { p_kind: kind.id })
    setBusy(false)
    if (error) return setErr(error.message)
    setKind(null)
    notify(`ส่งการแจ้งเตือนทดสอบแล้ว ถึง ${data} บัญชี`)
  }

  return (
    <>
      <Card>
        <H>ทดสอบการแจ้งเตือนในแอป</H>
        <p className="mb-4 text-slate-600">กดปุ่มเพื่อส่งการแจ้งเตือนทดสอบไปยังผู้ป่วยและญาติ/ผู้ดูแลทุกบัญชีที่เปิดใช้งาน ข้อความจะขึ้นต้นด้วย [ทดสอบ] ผู้รับต้องเปิดแอปค้างไว้ หรือเปิดแอปมาดูจึงจะเห็น</p>
        <div className="grid gap-4 sm:grid-cols-3">
          {KINDS.map((k) => (
            <div key={k.id} className="flex flex-col gap-3 rounded-2xl border border-slate-200 p-4">
              <div className="text-lg font-semibold">{k.title}</div>
              <div className="flex-1 text-sm text-slate-500">{k.hint}</div>
              <Btn onClick={() => { setErr(''); setKind(k) }}>ส่งทดสอบ</Btn>
            </div>
          ))}
        </div>
      </Card>
      {kind && (
        <Modal title="ส่งการแจ้งเตือนทดสอบ" onClose={() => setKind(null)}>
          <div className="space-y-4">
            <p>ส่ง <b>{kind.title.slice(3)}</b> ถึงผู้ป่วยและญาติ/ผู้ดูแลทุกบัญชีที่เปิดใช้งาน ใช่หรือไม่</p>
            {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
            <div className="flex justify-end gap-2"><Btn kind="ghost" onClick={() => setKind(null)}>ยกเลิก</Btn><Btn onClick={send}>{busy ? 'กำลังส่ง...' : 'ส่งเลย'}</Btn></div>
          </div>
        </Modal>
      )}
    </>
  )
}
