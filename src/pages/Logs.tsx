import { useEffect, useRef, useState } from 'react'
import writeExcelFile from 'write-excel-file/browser'
import { supabase } from '../supabase'
import { Badge, Btn, Card, Select, Table, inputCls } from '../ui'
import { logFilterToQuery, logRowToView, type LogRow, type LogView } from '../lib/plans'
import type { Ctx } from '../ctx'

// Quote every cell and neutralise a leading = + - @ tab or CR so Excel cannot run a note as a formula (CSV injection).
const cell = (v: unknown) => {
  const s = String(v ?? '')
  return '"' + (/^[=+\-@\t\r]/.test(s) ? "'" + s : s).replace(/"/g, '""') + '"'
}
console.assert(cell('=1+1') === `"'=1+1"` && cell('a"b') === '"a""b"' && cell(42) === '"42"', 'csv cell escaping')

const LIMIT = 200
const PAGE = 1000 // the API returns at most 1000 rows per request
const SELECT = 'id, scheduled_at, status, taken_at, is_late, medication_plans!inner(patient_id, patients(full_name), medicines(generic_name, trade_name))'
const STATUSES: [string, string][] = [['taken', 'ทานแล้ว'], ['late', 'เลท'], ['skipped', 'ยังไม่ได้ทาน']] // pending/missed rows show only under ทั้งหมด

export function Logs({ notify }: Ctx) {
  const [patients, setPatients] = useState<{ id: string; full_name: string }[]>([])
  const [patientId, setPatientId] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [status, setStatus] = useState('')
  const [rows, setRows] = useState<LogView[] | null>(null)
  const [err, setErr] = useState('')
  const seq = useRef(0) // drops answers that arrive after the filters changed again

  useEffect(() => {
    supabase.from('patients').select('id, full_name').order('full_name').then(({ data, error }) => {
      if (error) return notify('โหลดรายชื่อผู้ป่วยไม่สำเร็จ: ' + error.message)
      setPatients(data ?? [])
    })
  }, [])

  // the current filters as a query; !inner so the patient filter on the joined plan also drops the log rows, not just blanks the plan
  const filtered = () => {
    const f = logFilterToQuery({ patientId, from, to, status })
    let q = supabase.from('medication_logs').select(SELECT).order('scheduled_at', { ascending: false }).order('id')
    if (f.patientId) q = q.eq('medication_plans.patient_id', f.patientId)
    if (f.fromIso) q = q.gte('scheduled_at', f.fromIso)
    if (f.toIso) q = q.lt('scheduled_at', f.toIso)
    if (f.statusMatch) q = q.eq('status', f.statusMatch.status)
    if (f.statusMatch?.isLate !== undefined) q = q.eq('is_late', f.statusMatch.isLate)
    return q
  }

  useEffect(() => {
    const mine = ++seq.current
    setErr('')
    setRows(null)
    filtered().limit(LIMIT).then(({ data, error }) => {
      if (mine !== seq.current) return
      if (error) return setErr('โหลดประวัติการทานยาไม่สำเร็จ: ' + error.message)
      setRows((data as unknown as LogRow[]).map(logRowToView))
    })
  }, [patientId, from, to, status])

  // Excel export reads EVERY row matching the filters (page by page), not only the 200 on screen: it is meant for analysis
  const [exporting, setExporting] = useState(false)
  const exportXlsx = async () => {
    if (exporting) return
    setExporting(true)
    try {
      const all: LogView[] = []
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await filtered().range(from, from + PAGE - 1)
        if (error) return notify('ส่งออก Excel ไม่สำเร็จ: ' + error.message)
        all.push(...(data as unknown as LogRow[]).map(logRowToView))
        if ((data?.length ?? 0) < PAGE) break
      }
      const head = ['เวลาที่กำหนด', 'ผู้ป่วย', 'ยา', 'สถานะ', 'เวลาที่บันทึก'].map((value) => ({ value, fontWeight: 'bold' as const }))
      const body = all.map((l) => [l.scheduled, l.patient, l.medicine, l.statusLabel, l.takenAt].map((value) => ({ value })))
      await writeExcelFile([head, ...body], { sheet: 'ประวัติการทานยา', columns: [{ width: 20 }, { width: 24 }, { width: 24 }, { width: 16 }, { width: 14 }] }).toFile('medication-history.xlsx')
      notify(`ส่งออก Excel แล้ว ${all.length} รายการ`)
    } catch (e) {
      notify('ส่งออก Excel ไม่สำเร็จ: ' + (e instanceof Error ? e.message : String(e)))
    } finally {
      setExporting(false)
    }
  }

  const exportCsv = () => {
    const csv = ['เวลาที่กำหนด,ผู้ป่วย,ยา,สถานะ,เวลาที่บันทึก', ...(rows ?? []).map((l) => [l.scheduled, l.patient, l.medicine, l.statusLabel, l.takenAt].map(cell).join(','))].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }))
    a.download = 'medication-history.csv'; a.click(); notify('ส่งออก CSV แล้ว')
  }

  return (
    <Card>
      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
        <Select v={patientId} set={setPatientId} all="ทุกคน" opts={patients.map((p) => [p.id, p.full_name])} />
        <input type="date" aria-label="ตั้งแต่วันที่" className={inputCls + ' sm:w-auto'} value={from} max={to || undefined} onChange={(e) => setFrom(e.target.value)} />
        <input type="date" aria-label="ถึงวันที่" className={inputCls + ' sm:w-auto'} value={to} min={from || undefined} onChange={(e) => setTo(e.target.value)} />
        <Select v={status} set={setStatus} all="ทั้งหมด" opts={STATUSES} />
        <div className="flex gap-2 sm:ml-auto">{rows && rows.length > 0 && <><Btn onClick={exportXlsx} disabled={exporting}>{exporting ? 'กำลังส่งออก...' : 'ส่งออก Excel'}</Btn><Btn kind="ghost" onClick={exportCsv}>ส่งออก CSV</Btn></>}</div>
      </div>
      {err ? <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 ring-1 ring-red-200">{err}</div>
        : !rows ? <p className="py-8 text-center text-slate-400">กำลังโหลด...</p>
        : (
          <>
            {rows.length === LIMIT && <div className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900 ring-1 ring-amber-200">แสดง 200 รายการล่าสุด กรุณากรอกตัวกรองเพื่อจำกัดผลลัพธ์</div>}
            <Table head={['เวลาที่กำหนด', 'ผู้ป่วย', 'ยา', 'สถานะ', 'เวลาที่บันทึก']}
              rows={rows.map((l) => [l.scheduled, l.patient, l.medicine, <Badge tone={l.tone}>{l.statusLabel}</Badge>, l.takenAt])} />
          </>
        )}
    </Card>
  )
}
