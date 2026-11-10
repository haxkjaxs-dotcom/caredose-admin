import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { Btn, Card, H, Stat, Table } from '../ui'
import type { Ctx } from '../ctx'
import { dailyRate, fetchAllPages, needsFollow, thaiDay, thaiDayStartIso, todayCounts, type DashLog } from '../lib/dashboard'

const DAYS = 7
const DAY_MS = 86400000

export function Dashboard({ openPatient }: Ctx) {
  const [state, setState] = useState<{ patients: number; logs: DashLog[]; now: Date } | string | null>(null)

  useEffect(() => {
    const now = new Date()
    const from = thaiDayStartIso(thaiDay(new Date(now.getTime() - (DAYS - 1) * DAY_MS).toISOString()))
    Promise.all([
      supabase.from('patients').select('id', { count: 'exact', head: true }),
      // ordered by a unique key so pages never overlap or skip rows
      fetchAllPages<DashLog>((a, b) => supabase.from('medication_logs')
        .select('scheduled_at, status, is_late, medication_plans(patient_id, patients(full_name))')
        .gte('scheduled_at', from).order('scheduled_at').order('id').range(a, b) as unknown as PromiseLike<{ data: DashLog[] | null; error: { message: string } | null }>),
    ]).then(([p, l]) => {
      const err = p.error ?? l.error
      if (err) return setState('โหลดข้อมูลไม่สำเร็จ: ' + err.message)
      setState({ patients: p.count ?? 0, logs: l.data, now })
    })
  }, [])

  if (state === null) return <p className="py-8 text-center text-slate-400">กำลังโหลด...</p>
  if (typeof state === 'string') return <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{state}</div>

  const { patients, logs, now } = state
  const counts = todayCounts(logs, now)
  const rates = dailyRate(logs, now, DAYS)
  const follow = needsFollow(logs, now)
  return (
    <>
      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Stat label="ผู้ป่วยในความดูแล" value={patients} tone="gray" />
        <Stat label="ทานแล้ววันนี้" value={counts.taken} tone="green" />
        <Stat label="ทานเลทวันนี้" value={counts.late} tone="yellow" />
        <Stat label="ข้ามวันนี้" value={counts.skipped} tone="red" />
      </div>
      <Card>
        <H>สัดส่วนการทานยา {DAYS} วันล่าสุด (%)</H>
        <ul className="space-y-2">
          {rates.map((r) => (
            <li key={r.day} className="flex items-center gap-3">
              <span className="w-24 shrink-0 text-sm text-slate-500">{r.day}</span>
              <div className="h-4 flex-1 overflow-hidden rounded-full bg-slate-100">
                {r.rate !== null && <div className="h-full bg-brand-700" style={{ width: `${r.rate}%` }} />}
              </div>
              <span className="w-12 shrink-0 text-right text-sm font-medium">{r.rate === null ? '-' : `${r.rate}%`}</span>
            </li>
          ))}
        </ul>
        {logs.length === 0 && <p className="mt-3 text-center text-slate-400">ยังไม่มีข้อมูลการทานยา</p>}
      </Card>
      <Card>
        <H>ผู้ป่วยที่ต้องติดตามวันนี้</H>
        <Table
          head={['ผู้ป่วย', 'ข้าม', 'เลท', '']}
          rows={follow.map((f) => [f.name, f.skipped, f.late, <Btn kind="ghost" onClick={() => openPatient(f.patientId)}>ดูรายละเอียด</Btn>])}
        />
        {follow.length === 0 && <p className="mt-3 text-center text-slate-400">ไม่มีผู้ป่วยที่ต้องติดตามวันนี้</p>}
      </Card>
    </>
  )
}
