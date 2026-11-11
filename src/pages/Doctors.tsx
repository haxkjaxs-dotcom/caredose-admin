import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { Badge, Btn, Card } from '../ui'
import type { Ctx } from '../ctx'

type Doc = {
  id: string; full_name: string; department: string | null; specialty: string | null; phone: string | null; is_active: boolean
  patient_doctors: { active: boolean; patients: { full_name: string } | null }[]
}

export function Doctors({ role, notify }: Ctx) {
  const [docs, setDocs] = useState<Doc[]>([])
  const load = async () => {
    const { data, error } = await supabase.from('doctors').select('id, full_name, department, specialty, phone, is_active, patient_doctors(active, patients(full_name))').order('full_name')
    if (error) return notify('โหลดข้อมูลผู้ดูแลภาพรวมไม่สำเร็จ: ' + error.message)
    setDocs((data ?? []) as unknown as Doc[])
  }
  useEffect(() => { load() }, [])

  const toggle = async (d: Doc) => {
    // select() so an update that RLS silently filtered out (0 rows) is reported, not shown as success
    const { data, error } = await supabase.from('doctors').update({ is_active: !d.is_active }).eq('id', d.id).select('id')
    if (error) return notify('เปลี่ยนสถานะไม่สำเร็จ: ' + error.message)
    if (!data?.length) return notify('เปลี่ยนสถานะไม่สำเร็จ: ไม่มีสิทธิ์')
    load()
  }

  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {docs.map((d) => (
        <Card key={d.id}>
          <div className="flex items-start justify-between gap-2"><h3 className="text-lg font-semibold">{d.full_name}</h3><Badge tone={d.is_active ? 'green' : 'gray'}>{d.is_active ? 'ใช้งาน' : 'ปิดใช้งาน'}</Badge></div>
          <p className="mt-2 text-slate-600">{[d.department, d.specialty].filter(Boolean).join(' · ') || '-'}</p>
          <p className="text-slate-600">{d.phone ?? '-'}</p>
          <p className="mt-3 text-sm text-slate-500">ผู้ป่วยในความดูแล: {d.patient_doctors.filter((x) => x.active).map((x) => x.patients?.full_name).filter(Boolean).join(', ') || '-'}</p>
          {role === 'Admin' && (
            <div className="mt-4 flex gap-2">
              <Btn kind="ghost" onClick={() => toggle(d)}>{d.is_active ? 'ปิดใช้งาน' : 'เปิดใช้งาน'}</Btn>
            </div>
          )}
        </Card>
      ))}
      {!docs.length && <Card className="text-center text-slate-400 md:col-span-2 xl:col-span-3">ยังไม่มีข้อมูลผู้ดูแลภาพรวม</Card>}
    </div>
  )
}
