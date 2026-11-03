import * as D from '../data'
import type { Tone } from '../data'
import { Badge, Btn, Card, H, Stat, Table, followLabel, logTone, pName, fmt } from '../ui'
import type { Ctx } from '../ctx'

export function Dashboard({ patients, appts, openPatient, go, ids }: Ctx) {
  const follow = patients.filter((p) => p.follow === 'red' || p.follow === 'yellow')
  const upcoming = appts.filter((a) => a.status === 'รอนัด')
  const tl = D.logs.filter((l) => ids.has(l.patient) && (l.status === 'ข้าม' || l.status === 'ยังไม่บันทึก'))
  return (
    <>
      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Stat label="ผู้ป่วยในความดูแล" value={patients.length} tone="gray" />
        <Stat label="ทานยาครบตามแผน" value={patients.filter((p) => p.follow === 'green').length} tone="green" />
        <Stat label="ต้องติดตามวันนี้" value={follow.length} tone="red" />
        <Stat label="นัดหมายวันนี้" value={upcoming.length} tone="yellow" />
      </div>
      <div className="grid gap-6 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <H>สัดส่วนการทานยา (%)</H>
          {/* shortcut: placeholder until the chart reads medication_logs from Supabase */}
          <div className="flex h-52 items-center justify-center text-slate-400">ยังไม่มีข้อมูลการทานยา</div>
        </Card>
        <Card>
          <H action={<Btn kind="ghost" onClick={() => go('appts')}>ทั้งหมด</Btn>}>นัดหมายถัดไป</H>
          <ul className="space-y-3">
            {upcoming.map((a) => (
              <li key={a.id}>
                <button onClick={() => go('appts')} className="w-full rounded-xl border border-slate-200 p-3 text-left hover:bg-slate-50">
                  <div className="font-semibold">{pName(a.patient)}</div>
                  <div className="text-sm text-slate-500">{fmt(a.at)} · {a.reason}</div>
                </button>
              </li>
            ))}
            {!upcoming.length && <li className="text-slate-400">ไม่มีนัดหมาย</li>}
          </ul>
        </Card>
      </div>
      <Card>
        <H>ผู้ป่วยที่ต้องติดตาม</H>
        <Table
          head={['ผู้ป่วย', 'มื้อยา', 'สถานะการทานยา', 'สถานะการติดตาม', '']}
          rows={follow.map((p) => {
            const l = tl.find((x) => x.patient === p.id)
            return [p.name, l?.meal ?? '-', l ? <Badge tone={logTone[l.status]}>{l.status}</Badge> : '-', <Badge tone={p.follow as Tone}>{followLabel[p.follow as Tone]}</Badge>, <Btn kind="ghost" onClick={() => openPatient(p.id)}>ดูรายละเอียด</Btn>]
          })}
        />
      </Card>
    </>
  )
}
