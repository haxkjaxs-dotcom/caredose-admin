import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Field, H, Modal, Table, inputCls } from '../ui'
import type { Role } from '../ctx'

const ROLES: [string, string][] = [['admin', 'Admin'], ['doctor', 'ผู้ดูแลภาพรวม'], ['caregiver', 'ญาติ/ผู้ดูแล'], ['patient', 'ผู้ป่วย']]
const RANK = ROLES.map(([k]) => k) // highest first, a user with several roles shows the first
type U = { id: string; full_name: string | null; phone: string | null; is_active: boolean; role: string }
type Row = { id: number; at: string; actor: string | null; action: string; table_name: string | null; row_id: string | null }

export function Users({ role: myRole }: { role: Role }) {
  const isAdmin = myRole === 'Admin'
  const [me, setMe] = useState('')
  const [users, setUsers] = useState<U[]>([])
  const [audit, setAudit] = useState<Row[]>([])
  const [usage, setUsage] = useState<Record<string, { n: number; last: string }>>({}) // actor id -> audit actions
  const [patientOf, setPatientOf] = useState<Record<string, string>>({}) // user id -> linked patient name
  const [msg, setMsg] = useState('')
  const [form, setForm] = useState(false)
  const formRoles = isAdmin ? ROLES : ROLES.filter(([k]) => k === 'caregiver' || k === 'patient') // a doctor only makes ordinary accounts
  const [f, setF] = useState({ username: '', full_name: '', pin: '', role: isAdmin ? 'doctor' : 'patient' })
  const [formErr, setFormErr] = useState('')
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    const [p, r, a, pt] = await Promise.all([
      supabase.from('profiles').select('id, full_name, phone, is_active').order('user_no'),
      supabase.from('user_roles').select('user_id, role'),
      // shortcut: usage counts cover only the latest 1000 audit rows, move to a grouped RPC when the log outgrows that
      supabase.from('audit_logs').select('id, at, actor, action, table_name, row_id').order('at', { ascending: false }).limit(1000),
      supabase.from('patients').select('full_name, user_id').not('user_id', 'is', null),
    ])
    const bad = p.error ?? r.error ?? a.error ?? pt.error
    if (bad) return setMsg('โหลดข้อมูลไม่สำเร็จ: ' + bad.message)
    const roleOf = (id: string) => RANK.find((k) => (r.data ?? []).some((x) => x.user_id === id && x.role === k)) ?? 'none'
    setUsers((p.data ?? []).map((u) => ({ ...u, role: roleOf(u.id) })))
    setAudit((a.data ?? []).slice(0, 20))
    const use: Record<string, { n: number; last: string }> = {}
    for (const x of a.data ?? []) if (x.actor) use[x.actor] = { n: (use[x.actor]?.n ?? 0) + 1, last: use[x.actor]?.last ?? x.at } // newest first
    setUsage(use)
    setPatientOf(Object.fromEntries((pt.data ?? []).map((x) => [x.user_id as string, x.full_name as string])))
  }, [])

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setMe(data.session?.user.id ?? ''))
    load()
  }, [load])

  const log = (action: string, row_id: string, old_value: object, new_value: object) =>
    supabase.from('audit_logs').insert({ actor: me, action, table_name: 'profiles/user_roles', row_id, old_value, new_value })

  // Add the new role first, then drop the others: the user is never left without a role.
  const setRole = async (u: U, role: string) => {
    const ins = await supabase.from('user_roles').upsert({ user_id: u.id, role }, { onConflict: 'user_id,role', ignoreDuplicates: true })
    if (ins.error) return setMsg('เปลี่ยนสิทธิ์ไม่สำเร็จ: ' + ins.error.message)
    // keep the doctors / caregivers lists in step with the role: a row exists while the role does, a doctor row is off otherwise
    const name = u.full_name ?? u.phone ?? '-'
    if (role === 'doctor') {
      const { data } = await supabase.from('doctors').select('id').eq('user_id', u.id).maybeSingle()
      if (!data) await supabase.from('doctors').insert({ user_id: u.id, full_name: name, is_active: u.is_active })
      else await supabase.from('doctors').update({ is_active: u.is_active }).eq('id', data.id)
    } else if (u.role === 'doctor') {
      await supabase.from('doctors').update({ is_active: false }).eq('user_id', u.id)
    }
    if (role === 'caregiver') {
      const { data } = await supabase.from('caregivers').select('id').eq('user_id', u.id).maybeSingle()
      if (!data) await supabase.from('caregivers').insert({ user_id: u.id, full_name: name, phone: u.phone })
    }
    const del = await supabase.from('user_roles').delete().eq('user_id', u.id).neq('role', role)
    if (del.error) return setMsg('ลบสิทธิ์เดิมไม่สำเร็จ: ' + del.error.message)
    await log('change_role', u.id, { role: u.role }, { role })
    setMsg('บันทึกสิทธิ์แล้ว')
    load()
  }

  const toggle = async (u: U) => {
    const { error } = await supabase.from('profiles').update({ is_active: !u.is_active }).eq('id', u.id)
    if (error) return setMsg('เปลี่ยนสถานะไม่สำเร็จ: ' + error.message)
    await supabase.from('doctors').update({ is_active: !u.is_active }).eq('user_id', u.id) // the doctors list mirrors the account status
    await log('set_active', u.id, { is_active: u.is_active }, { is_active: !u.is_active })
    load()
  }

  // the DB trigger (integration.sql 20) carries the new name to the patients / caregivers / doctors row of this account
  const rename = async (u: U) => {
    const name = window.prompt('ชื่อ-นามสกุลใหม่', u.full_name ?? '')?.trim()
    if (!name || name === u.full_name) return
    const { data, error } = await supabase.from('profiles').update({ full_name: name }).eq('id', u.id).select('id')
    if (error) return setMsg('แก้ชื่อไม่สำเร็จ: ' + error.message)
    if (!data?.length) return setMsg('แก้ชื่อไม่สำเร็จ: ไม่มีสิทธิ์')
    setMsg('แก้ชื่อแล้ว')
    load()
  }

  const remove = async (u: U) => {
    if (!window.confirm(`ลบบัญชี "${u.full_name ?? u.phone ?? '-'}" ถาวร? ลบแล้วเข้าสู่ระบบไม่ได้อีก`)) return
    const { error } = await supabase.rpc('delete_user', { p_user_id: u.id })
    if (error) return setMsg('ลบบัญชีไม่สำเร็จ: ' + error.message)
    setMsg('ลบบัญชีแล้ว')
    load()
  }

  const create = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    setBusy(true)
    setFormErr('')
    const { error } = await supabase.functions.invoke('create-user', { body: f })
    setBusy(false)
    if (error) {
      const body = error instanceof FunctionsHttpError ? await error.context.json().catch(() => null) : null
      return setFormErr(body?.error ?? error.message)
    }
    setForm(false)
    setF({ username: '', full_name: '', pin: '', role: formRoles[0][0] })
    setMsg('สร้างบัญชีแล้ว')
    load()
  }

  const nameOf = (id: string | null) => users.find((u) => u.id === id)?.full_name ?? '-'
  const staff = users.filter((u) => u.role === 'admin' || u.role === 'doctor')
  const general = users.filter((u) => u.role !== 'admin' && u.role !== 'doctor')
  // Admin edits any account except their own. ผู้ดูแลภาพรวม edits only the non-staff table (caregiver / patient) and cannot
  // delete or grant admin / doctor; their own row is locked too. Cosmetic: roles_i / roles_d / profiles_u decide.
  // The staff table also shows how much each account uses the system (audit log, admin only: audit_logs is admin-read).
  const accounts = (list: U[], staffTable: boolean) => (
        <Table
          head={['ชื่อ', 'ชื่อผู้ใช้ / เบอร์', 'สิทธิ์', 'สถานะ', ...(staffTable && isAdmin ? ['การใช้งาน', 'ใช้งานล่าสุด'] : []), '']}
          rows={list.map((u) => [
            <div><b>{u.full_name ?? '-'}</b>{patientOf[u.id] && <div className="text-xs text-slate-500">ผู้ป่วย: {patientOf[u.id]}</div>}</div>, u.phone ?? '-',
            u.id === me || (staffTable && !isAdmin) ? <Badge tone="gray">{ROLES.find(([k]) => k === u.role)?.[1] ?? 'ไม่มีสิทธิ์'}</Badge> : (
              <select className={inputCls + ' !w-auto'} value={u.role} onChange={(e) => setRole(u, e.target.value)}>
                {u.role === 'none' && <option value="none" disabled>ไม่มีสิทธิ์</option>}
                {formRoles.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            ),
            <Badge tone={u.is_active ? 'green' : 'gray'}>{u.is_active ? 'ใช้งาน' : 'ปิดใช้งาน'}</Badge>,
            ...(staffTable && isAdmin ? [usage[u.id] ? `${usage[u.id].n} ครั้ง` : '-', usage[u.id] ? new Date(usage[u.id].last).toLocaleString('th-TH') : 'ยังไม่มีการใช้งาน'] : []),
            u.id === me ? <span className="text-sm text-slate-400">บัญชีของคุณ</span> : staffTable && !isAdmin ? <span className="text-sm text-slate-400">แก้ไขไม่ได้</span> : (
              <div className="flex gap-2">
                <Btn kind="ghost" onClick={() => rename(u)}>แก้ชื่อ</Btn>
                <Btn kind="ghost" onClick={() => toggle(u)}>{u.is_active ? 'ปิดบัญชี' : 'เปิดบัญชี'}</Btn>
                {isAdmin && <Btn kind="danger" onClick={() => remove(u)}>ลบ</Btn>}
              </div>
            ),
          ])}
        />
  )

  return (
    <>
      {msg && <div role="status" className="rounded-xl bg-brand-50 p-3 text-brand-900 ring-1 ring-brand-100">{msg}</div>}
      <Card>
        <H action={isAdmin && <Btn onClick={() => setForm(true)}>เพิ่มผู้ใช้</Btn>}>Admin และผู้ดูแลภาพรวม ({staff.length})</H>
        {accounts(staff, true)}
      </Card>
      <Card>
        <H action={!isAdmin && <Btn onClick={() => setForm(true)}>เพิ่มผู้ใช้</Btn>}>ผู้ใช้งานทั่วไป: ผู้ป่วยและญาติ/ผู้ดูแล ({general.length})</H>
        {accounts(general, false)}
      </Card>
      {isAdmin && <Card>
        <H>Audit Log</H>
        <Table head={['เวลา', 'ผู้ดำเนินการ', 'การกระทำ', 'รายการ']} rows={audit.map((a) => [new Date(a.at).toLocaleString('th-TH'), nameOf(a.actor), a.action, `${a.table_name ?? ''} ${a.row_id ?? ''}`])} />
      </Card>}
      {form && (
        <Modal title="เพิ่มผู้ใช้" onClose={() => setForm(false)}>
          <form onSubmit={create} className="space-y-4">
            <Field label="ชื่อ-นามสกุล"><input className={inputCls} value={f.full_name} onChange={(e) => setF({ ...f, full_name: e.target.value })} /></Field>
            <Field label="ชื่อผู้ใช้หรือเบอร์โทร (ใช้ login)"><input className={inputCls} maxLength={30} value={f.username} onChange={(e) => setF({ ...f, username: e.target.value.replace(/\W/g, '') })} /></Field>
            <Field label="PIN 6 หลัก"><input className={inputCls} inputMode="numeric" maxLength={6} value={f.pin} onChange={(e) => setF({ ...f, pin: e.target.value.replace(/\D/g, '') })} /></Field>
            <Field label="สิทธิ์">
              <select className={inputCls} value={f.role} onChange={(e) => setF({ ...f, role: e.target.value })}>{formRoles.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
            </Field>
            {formErr && <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{formErr}</div>}
            <div className="flex justify-end"><Btn>{busy ? 'กำลังสร้าง...' : 'สร้างบัญชี'}</Btn></div>
          </form>
        </Modal>
      )}
    </>
  )
}
