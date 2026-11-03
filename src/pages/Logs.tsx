import { useState } from 'react'
import * as D from '../data'
import { Badge, Btn, Card, Search, Select, Table, logTone, mName, pName } from '../ui'
import type { Ctx } from '../ctx'

// Quote every cell and neutralise a leading = + - @ tab or CR so Excel cannot run a note as a formula (CSV injection).
const cell = (v: unknown) => {
  const s = String(v ?? '')
  return '"' + (/^[=+\-@\t\r]/.test(s) ? "'" + s : s).replace(/"/g, '""') + '"'
}
console.assert(cell('=1+1') === `"'=1+1"` && cell('a"b') === '"a""b"' && cell(42) === '"42"', 'csv cell escaping')

export function Logs({ ids, notify }: Ctx) {
  const [q, setQ] = useState(''); const [st, setSt] = useState('')
  const rows = D.logs.filter((l) => ids.has(l.patient) && pName(l.patient).includes(q) && (!st || l.status === st))
  const exportCsv = () => {
    const csv = ['วันที่เวลา,ผู้ป่วย,ยา,มื้อ,สถานะ,ผู้บันทึก,หมายเหตุ', ...rows.map((l) => [l.at, pName(l.patient), mName(l.med), l.meal, l.status, l.by, l.note].map(cell).join(","))].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }))
    a.download = 'medication-history.csv'; a.click(); notify('ส่งออก CSV แล้ว')
  }
  const missed = rows.filter((l) => l.status === 'ข้าม' || l.status === 'ยังไม่บันทึก').length
  return (
    <Card>
      {missed > 0 && <div className="mb-4 rounded-xl bg-red-50 p-3 text-red-800 ring-1 ring-red-200">แจ้งเตือน: พบรายการพลาดยา/ยังไม่บันทึก {missed} รายการ</div>}
      <div className="mb-4 flex flex-col gap-3 sm:flex-row">
        <Search v={q} set={setQ} ph="ค้นหาชื่อผู้ป่วย" />
        <Select v={st} set={setSt} all="ทุกสถานะ" opts={['ทานแล้ว', 'เลท', 'ข้าม', 'ยังไม่บันทึก'].map((s) => [s, s])} />
        <div className="sm:ml-auto"><Btn kind="ghost" onClick={exportCsv}>ส่งออก CSV</Btn></div>
      </div>
      <Table head={['วันที่และเวลา', 'ผู้ป่วย', 'ยา', 'มื้อ', 'สถานะ', 'ผู้บันทึก', 'หมายเหตุ']} rows={rows.map((l) => [l.at, pName(l.patient), mName(l.med), l.meal, <Badge tone={logTone[l.status]}>{l.status}</Badge>, l.by, l.note || '-'])} />
    </Card>
  )
}
