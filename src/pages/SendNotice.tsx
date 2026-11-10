import { useState, type FormEvent } from 'react'
import { supabase } from '../supabase'
import { Btn, Field, Modal, inputCls } from '../ui'
import { noticeRpcArgs, validateNotice } from '../lib/notices'

// the database (send_notification) is the permission gate; the caller only hides the button
export function SendNotice({ patientId, patientName, notify, onClose }: { patientId: string; patientName: string; notify: (m: string) => void; onClose: () => void }) {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    const bad = validateNotice(title, body)
    if (bad) return setErr(bad)
    setBusy(true)
    setErr('')
    const { error } = await supabase.rpc('send_notification', noticeRpcArgs(patientId, title, body))
    setBusy(false)
    if (error) return setErr(error.message)
    notify('ส่งข้อความแล้ว')
    onClose()
  }

  return (
    <Modal title={`ส่งข้อความถึง ${patientName}`} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="หัวข้อ *"><input className={inputCls} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <Field label="ข้อความ *"><textarea className={inputCls} rows={4} value={body} onChange={(e) => setBody(e.target.value)} /></Field>
        <p className="text-sm text-slate-500">ข้อความนี้ผู้ป่วยจะเห็นในแอป อย่าใส่ข้อมูลสุขภาพที่ละเอียดอ่อน</p>
        {err && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>}
        <div className="flex justify-end"><Btn disabled={busy}>{busy ? 'กำลังส่ง...' : 'ส่งข้อความ'}</Btn></div>
      </form>
    </Modal>
  )
}
