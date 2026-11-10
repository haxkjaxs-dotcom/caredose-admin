import { describe, expect, it } from 'vitest'
import { dailyRate, needsFollow, thaiDay, thaiDayStartIso, todayCounts, type DashLog } from './dashboard'

// 2026-11-10 12:00 in Thailand (UTC+7)
const NOW = new Date('2026-11-10T05:00:00Z')
const log = (scheduled_at: string, status: DashLog['status'], is_late = false, patient = 'p1', name = 'สมชาย'): DashLog => ({
  scheduled_at, status, is_late, medication_plans: { patient_id: patient, patients: { full_name: name } },
})

describe('thaiDay', () => {
  it('uses Thai time, not UTC', () => {
    expect(thaiDay('2026-11-09T17:10:00Z')).toBe('2026-11-10') // 00:10 Thai
    expect(thaiDay('2026-11-10T16:30:00Z')).toBe('2026-11-10') // 23:30 Thai
    expect(thaiDay('2026-11-10T17:00:00Z')).toBe('2026-11-11') // 00:00 Thai next day
  })
  it('thaiDayStartIso is midnight Thai in UTC', () => {
    expect(thaiDayStartIso('2026-11-10')).toBe('2026-11-09T17:00:00.000Z')
  })
})

describe('todayCounts', () => {
  it('counts only today (Thai), splits taken / late / skipped, ignores pending and missed', () => {
    const logs = [
      log('2026-11-10T01:00:00Z', 'taken'),
      log('2026-11-10T02:00:00Z', 'taken', true),
      log('2026-11-10T03:00:00Z', 'skipped'),
      log('2026-11-10T04:00:00Z', 'pending'),
      log('2026-11-10T04:30:00Z', 'missed'),
      log('2026-11-09T16:59:00Z', 'taken'), // 23:59 Thai yesterday
      log('2026-11-10T17:00:00Z', 'taken'), // 00:00 Thai tomorrow
    ]
    expect(todayCounts(logs, NOW)).toEqual({ taken: 1, late: 1, skipped: 1 })
  })
  it('is all zeros with no logs', () => {
    expect(todayCounts([], NOW)).toEqual({ taken: 0, late: 0, skipped: 0 })
  })
})

describe('dailyRate', () => {
  it('returns `days` entries oldest to newest ending today', () => {
    const r = dailyRate([], NOW, 7)
    expect(r.map((x) => x.day)).toEqual(['2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08', '2026-11-09', '2026-11-10'])
  })
  it('is null (not 0) for a day without taken/skipped logs, and ignores pending', () => {
    const r = dailyRate([log('2026-11-09T01:00:00Z', 'pending')], NOW, 3)
    expect(r.map((x) => x.rate)).toEqual([null, null, null])
  })
  it('is taken / (taken + skipped) as a rounded percent; late counts as taken; 0 when all skipped', () => {
    const logs = [
      log('2026-11-10T01:00:00Z', 'taken'), log('2026-11-10T02:00:00Z', 'skipped'),
      log('2026-11-09T01:00:00Z', 'taken'), log('2026-11-09T02:00:00Z', 'taken', true), log('2026-11-09T03:00:00Z', 'skipped'),
      log('2026-11-08T01:00:00Z', 'skipped'),
    ]
    expect(dailyRate(logs, NOW, 3).map((x) => x.rate)).toEqual([0, 67, 50])
  })
  it('puts a 23:30 Thai dose on that Thai day', () => {
    const r = dailyRate([log('2026-11-09T16:30:00Z', 'taken')], NOW, 2)
    expect(r).toEqual([{ day: '2026-11-09', rate: 100 }, { day: '2026-11-10', rate: null }])
  })
})

describe('needsFollow', () => {
  it('lists patients with a skipped or late dose today, most skipped first, with their name', () => {
    const logs = [
      log('2026-11-10T01:00:00Z', 'skipped', false, 'a', 'เอ'),
      log('2026-11-10T02:00:00Z', 'taken', true, 'b', 'บี'),
      log('2026-11-10T03:00:00Z', 'skipped', false, 'b', 'บี'),
      log('2026-11-10T04:00:00Z', 'skipped', false, 'b', 'บี'),
      log('2026-11-10T01:00:00Z', 'taken', false, 'c', 'ซี'),
      log('2026-11-09T01:00:00Z', 'skipped', false, 'd', 'ดี'), // yesterday
    ]
    expect(needsFollow(logs, NOW)).toEqual([
      { patientId: 'b', name: 'บี', skipped: 2, late: 1 },
      { patientId: 'a', name: 'เอ', skipped: 1, late: 0 },
    ])
  })
  it('skips logs without a plan row', () => {
    const orphan: DashLog = { scheduled_at: '2026-11-10T01:00:00Z', status: 'skipped', is_late: false, medication_plans: null }
    expect(needsFollow([orphan], NOW)).toEqual([])
  })
})
