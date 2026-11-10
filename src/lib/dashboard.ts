export type DashLog = {
  scheduled_at: string
  status: 'pending' | 'taken' | 'skipped' | 'missed'
  is_late: boolean
  medication_plans: { patient_id: string; patients: { full_name: string } | null } | null
}

const THAI_OFFSET_MS = 7 * 3600 * 1000

// yyyy-mm-dd of an instant in Thailand (UTC+7, no DST)
export const thaiDay = (iso: string): string => new Date(new Date(iso).getTime() + THAI_OFFSET_MS).toISOString().slice(0, 10)

// the instant a Thai calendar day starts, as an ISO string for `gte` filters
export const thaiDayStartIso = (day: string): string => new Date(`${day}T00:00:00+07:00`).toISOString()

const today = (now: Date) => thaiDay(now.toISOString())

export function todayCounts(logs: DashLog[], now: Date): { taken: number; late: number; skipped: number } {
  const day = today(now)
  const out = { taken: 0, late: 0, skipped: 0 }
  for (const l of logs) {
    if (thaiDay(l.scheduled_at) !== day) continue
    if (l.status === 'taken') l.is_late ? out.late++ : out.taken++
    else if (l.status === 'skipped') out.skipped++
  }
  return out
}

// oldest -> newest, ending today. rate = taken (late included) / (taken + skipped); null when neither exists that day.
export function dailyRate(logs: DashLog[], now: Date, days: number): { day: string; rate: number | null }[] {
  const todayMs = new Date(now.getTime() + THAI_OFFSET_MS).setUTCHours(0, 0, 0, 0)
  const tally = new Map<string, { taken: number; skipped: number }>()
  for (const l of logs) {
    if (l.status !== 'taken' && l.status !== 'skipped') continue
    const t = tally.get(thaiDay(l.scheduled_at)) ?? { taken: 0, skipped: 0 }
    l.status === 'taken' ? t.taken++ : t.skipped++
    tally.set(thaiDay(l.scheduled_at), t)
  }
  return Array.from({ length: days }, (_, i) => {
    const day = new Date(todayMs - (days - 1 - i) * 86400000).toISOString().slice(0, 10)
    const t = tally.get(day)
    const total = t ? t.taken + t.skipped : 0
    return { day, rate: total ? Math.round((t!.taken / total) * 100) : null }
  })
}

// today's patients with a skipped or late dose, most skipped first
export function needsFollow(logs: DashLog[], now: Date): { patientId: string; name: string; skipped: number; late: number }[] {
  const day = today(now)
  const by = new Map<string, { patientId: string; name: string; skipped: number; late: number }>()
  for (const l of logs) {
    const plan = l.medication_plans
    if (!plan || thaiDay(l.scheduled_at) !== day) continue
    const isSkip = l.status === 'skipped'
    const isLate = l.status === 'taken' && l.is_late
    if (!isSkip && !isLate) continue
    const e = by.get(plan.patient_id) ?? { patientId: plan.patient_id, name: plan.patients?.full_name ?? '-', skipped: 0, late: 0 }
    if (isSkip) e.skipped++
    else e.late++
    by.set(plan.patient_id, e)
  }
  return [...by.values()].sort((a, b) => b.skipped - a.skipped || b.late - a.late)
}

type Page<T> = { data: T[] | null; error: { message: string } | null }

// PostgREST caps one response at 1000 rows without saying so, so read page by page until a short page.
// Any failing page fails the whole read: partial data would give plausible but wrong dashboard numbers.
export async function fetchAllPages<T>(
  fetchPage: (from: number, to: number) => PromiseLike<Page<T>>,
  pageSize = 1000,
): Promise<{ data: T[]; error: { message: string } | null }> {
  const all: T[] = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await fetchPage(from, from + pageSize - 1)
    if (error) return { data: [], error }
    const rows = data ?? []
    all.push(...rows)
    if (rows.length < pageSize) return { data: all, error: null }
  }
}
