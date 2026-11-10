export const isThaiMobile = (s: string) => /^0[689]\d{8}$/.test(s.replace(/[\s-]/g, ''))

// Same rule as SQL norm_phone: digits only, leading 66 -> 0.
export const normalizePhoneDigits = (s: string) => s.replace(/\D/g, '').replace(/^66/, '0')

// ids of patients whose normalised (non-empty) phone is shared with another patient
export function samePhoneGroups(patients: { id: string; phone: string | null }[]): Set<string> {
  const byPhone = new Map<string, string[]>()
  for (const p of patients) {
    const n = normalizePhoneDigits(p.phone ?? '')
    if (n) byPhone.set(n, [...(byPhone.get(n) ?? []), p.id])
  }
  return new Set([...byPhone.values()].filter((ids) => ids.length > 1).flat())
}

export const isHHmm = (s: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(s)

export const normalizeTimes = (list: string[]) => [...new Set(list.map((t) => t.trim()).filter(Boolean))].sort()

export type RuleKind = 'daily' | 'weekdays' | 'interval'
// index = ISO weekday - 1 (1 = Monday ... 7 = Sunday), the numbering save_plan and the app use
export const WEEKDAY_NAMES = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์']

export function ruleLabel(days: number[] | null, interval: number | null): string {
  if (days && days.length > 0 && days.length < 7) return [...days].sort((a, b) => a - b).map((d) => WEEKDAY_NAMES[d - 1]).join('/')
  if (interval) return `ทุก ${interval} วัน`
  return 'ทุกวัน'
}

const isIntervalText = (s: string) => /^\d+$/.test(s) && Number(s) >= 2 && Number(s) <= 365

export function validatePlanForm(f: { medicineId: string; dose: string; start: string; end: string; times: string[]; ruleKind: RuleKind; days: number[]; interval: string }): string | null {
  if (!f.medicineId) return 'เลือกยา'
  if (!f.dose.trim()) return 'กรอกขนาดยา'
  if (!f.start) return 'กรอกวันเริ่ม'
  if (f.end && f.end < f.start) return 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม' // ISO yyyy-mm-dd compares lexically
  if (f.times.length === 0 || !f.times.every(isHHmm)) return 'เพิ่มเวลาทานอย่างน้อย 1 เวลา (รูป HH:mm)'
  if (f.ruleKind === 'weekdays' && f.days.length === 0) return 'เลือกวันที่ทานอย่างน้อย 1 วัน'
  if (f.ruleKind === 'interval' && !isIntervalText(f.interval)) return 'ทุก N วัน: N ต้องเป็นจำนวนเต็ม 2-365'
  return null
}

export function logStatusLabel(status: 'pending' | 'taken' | 'skipped' | 'missed', isLate: boolean): string {
  if (status === 'taken') return isLate ? 'เลท' : 'ทานแล้ว'
  if (status === 'skipped') return 'ยังไม่ได้ทาน'
  return 'ยังไม่บันทึก'
}

export type PlanRow = {
  id: string; medicine_id: string; dose: string; meal_relation: string | null; start_date: string; end_date: string | null
  status: string; doctor_note: string | null
  medicines: { generic_name: string; trade_name: string | null } | null
  medication_schedules: { time_of_day: string; days_of_week?: number[] | null; interval_days?: number | null }[] | null
}

// Postgres `time` comes back as 08:00:00: slice to HH:mm
export function planRowToView(r: PlanRow) {
  // save_plan writes one rule on every row of a plan; if rows ever disagree, the earliest time wins (same as the app)
  const first = [...(r.medication_schedules ?? [])].sort((a, b) => a.time_of_day.localeCompare(b.time_of_day))[0]
  const days = first?.days_of_week?.length ? [...first.days_of_week].sort((a, b) => a - b) : []
  const intervalDays = first?.interval_days ?? null
  const ruleKind: RuleKind = days.length ? 'weekdays' : intervalDays ? 'interval' : 'daily'
  return {
    id: r.id, medicineId: r.medicine_id,
    name: r.medicines?.trade_name || r.medicines?.generic_name || '-',
    dose: r.dose, meal: r.meal_relation ?? '', start: r.start_date, end: r.end_date ?? '',
    range: `${r.start_date} – ${r.end_date ?? 'ไม่กำหนดวันสิ้นสุด'}`,
    times: (r.medication_schedules ?? []).map((s) => s.time_of_day.slice(0, 5)).sort(),
    note: r.doctor_note ?? '', status: r.status, statusLabel: r.status === 'active' ? 'ใช้งาน' : 'หยุดแล้ว',
    rule: ruleLabel(days, intervalDays), ruleKind, days, interval: ruleKind === 'interval' ? String(intervalDays) : '',
  }
}
export type PlanView = ReturnType<typeof planRowToView>

export type PlanForm = { id: string | null; medicineId: string; dose: string; meal: string; start: string; end: string; note: string; times: string[]; status: string; ruleKind: RuleKind; days: number[]; interval: string }

// status is carried through so editing a stopped plan does not re-activate it
export const planToForm = (v: PlanView): PlanForm => ({
  id: v.id, medicineId: v.medicineId, dose: v.dose, meal: v.meal, start: v.start, end: v.end, note: v.note,
  times: v.times.length ? v.times : [''], status: v.status, ruleKind: v.ruleKind, days: v.days, interval: v.interval,
})

export const planRpcArgs = (patientId: string, f: PlanForm, times: string[], status = f.status) => ({
  p_plan_id: f.id, p_patient_id: patientId, p_medicine_id: f.medicineId, p_dose: f.dose, p_meal_relation: f.meal || null,
  p_start: f.start, p_end: f.end || null, p_note: f.note || null, p_times: times, p_status: status,
  p_days_of_week: f.ruleKind === 'weekdays' ? [...f.days].sort((a, b) => a - b) : null,
  p_interval_days: f.ruleKind === 'interval' ? Number(f.interval) : null,
})

export type LogRow = {
  id: string; scheduled_at: string; status: 'pending' | 'taken' | 'skipped' | 'missed'; taken_at: string | null; is_late: boolean
  medication_plans: { patient_id: string; patients: { full_name: string } | null; medicines: { generic_name: string; trade_name: string | null } | null } | null
}

const THAI_MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']
const hm = (d: Date) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
// `d MMM yyyy HH:mm` in the machine's local zone, Thai month and Buddhist year (same convention as the th-TH formatter in ui.tsx)
export const fmtLocal = (iso: string) => { const d = new Date(iso); return `${d.getDate()} ${THAI_MONTHS[d.getMonth()]} ${d.getFullYear() + 543} ${hm(d)}` }

export function logRowToView(r: LogRow) {
  const label = logStatusLabel(r.status, r.is_late)
  const med = r.medication_plans?.medicines
  return {
    id: r.id,
    patient: r.medication_plans?.patients?.full_name || '-',
    medicine: med?.trade_name || med?.generic_name || '-',
    statusLabel: label,
    tone: label === 'ทานแล้ว' ? 'green' as const : label === 'เลท' ? 'yellow' as const : 'gray' as const,
    scheduled: fmtLocal(r.scheduled_at),
    takenAt: r.taken_at ? hm(new Date(r.taken_at)) : '-',
  }
}
export type LogView = ReturnType<typeof logRowToView>

export type LogFilter = { patientId: string; from: string; to: string; status: string } // from/to: yyyy-mm-dd (local day), status: '' | taken | late | skipped
const localDay = (s: string, plus = 0) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d + plus).toISOString() }

// fromIso is inclusive (start of the local day); toIso is EXCLUSIVE: the start of the day after `to`, so query with gte/lt
export function logFilterToQuery(f: LogFilter) {
  const q: { patientId?: string; fromIso?: string; toIso?: string; statusMatch?: { status: 'taken' | 'skipped'; isLate?: boolean } } = {}
  if (f.patientId) q.patientId = f.patientId
  if (f.from) q.fromIso = localDay(f.from)
  if (f.to) q.toIso = localDay(f.to, 1)
  if (f.status === 'taken') q.statusMatch = { status: 'taken', isLate: false }
  else if (f.status === 'late') q.statusMatch = { status: 'taken', isLate: true }
  else if (f.status === 'skipped') q.statusMatch = { status: 'skipped' }
  return q
}
