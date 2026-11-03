import { useState } from 'react'
import * as D from '../data'
import { Badge, Btn, Card } from '../ui'
import type { Ctx } from '../ctx'

export function Doctors({ role }: Ctx) {
  const [docs, setDocs] = useState(D.doctors)
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {docs.map((d) => (
        <Card key={d.id}>
          <div className="flex items-start justify-between gap-2"><h3 className="text-lg font-semibold">{d.name}</h3><Badge tone={d.active ? 'green' : 'gray'}>{d.active ? 'ใช้งาน' : 'ปิดใช้งาน'}</Badge></div>
          <p className="mt-2 text-slate-600">{d.dept} · {d.spec}</p>
          <p className="text-slate-600">{d.phone}</p>
          <p className="mt-3 text-sm text-slate-500">ผู้ป่วยในความดูแล: {D.patients.filter((p) => p.doctor === d.id).map((p) => p.name).join(', ') || '-'}</p>
          {role === 'Admin' && <div className="mt-4"><Btn kind="ghost" onClick={() => setDocs(docs.map((x) => (x.id === d.id ? { ...x, active: !x.active } : x)))}>{d.active ? 'ปิดใช้งาน' : 'เปิดใช้งาน'}</Btn></div>}
        </Card>
      ))}
      {!docs.length && <Card className="text-center text-slate-400 md:col-span-2 xl:col-span-3">ยังไม่มีข้อมูลแพทย์</Card>}
    </div>
  )
}
