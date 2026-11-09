import { describe, expect, it } from 'vitest'
import { isHHmm, isThaiMobile, logStatusLabel, normalizeTimes, planRowToView, planToForm, planRpcArgs, validatePlanForm } from './plans'

describe('isThaiMobile', () => {
  it('accepts 10 digits starting 06/08/09, ignoring spaces and dashes', () => {
    expect(isThaiMobile('081-234-5678')).toBe(true)
    expect(isThaiMobile('0812345678')).toBe(true)
    expect(isThaiMobile(' 09 1234 5678 ')).toBe(true)
    expect(isThaiMobile('0612345678')).toBe(true)
  })
  it('rejects others', () => {
    expect(isThaiMobile('0212345678')).toBe(false)
    expect(isThaiMobile('081234567')).toBe(false)
    expect(isThaiMobile('')).toBe(false)
  })
})

describe('isHHmm', () => {
  it('accepts valid', () => {
    expect(isHHmm('08:00')).toBe(true)
    expect(isHHmm('23:59')).toBe(true)
  })
  it('rejects invalid', () => {
    expect(isHHmm('8:00')).toBe(false)
    expect(isHHmm('24:00')).toBe(false)
    expect(isHHmm('12:60')).toBe(false)
  })
})

describe('normalizeTimes', () => {
  it('drops empty, dedupes, sorts', () => {
    expect(normalizeTimes(['18:00', '08:00', '08:00', ''])).toEqual(['08:00', '18:00'])
  })
})

describe('validatePlanForm', () => {
  const ok = { medicineId: 'm1', dose: '1 เม็ด', start: '2026-01-01', end: '2026-01-31', times: ['08:00'] }
  it('returns null when valid', () => {
    expect(validatePlanForm(ok)).toBeNull()
    expect(validatePlanForm({ ...ok, end: '' })).toBeNull()
    expect(validatePlanForm({ ...ok, end: ok.start })).toBeNull()
  })
  it('returns Thai messages', () => {
    expect(validatePlanForm({ ...ok, medicineId: '' })).toBe('เลือกยา')
    expect(validatePlanForm({ ...ok, dose: '  ' })).toBe('กรอกขนาดยา')
    expect(validatePlanForm({ ...ok, start: '' })).toBe('กรอกวันเริ่ม')
    expect(validatePlanForm({ ...ok, end: '2025-12-31' })).toBe('วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม')
    expect(validatePlanForm({ ...ok, times: [] })).toBe('เพิ่มเวลาทานอย่างน้อย 1 เวลา (รูป HH:mm)')
    expect(validatePlanForm({ ...ok, times: ['8:00'] })).toBe('เพิ่มเวลาทานอย่างน้อย 1 เวลา (รูป HH:mm)')
  })
})

describe('logStatusLabel', () => {
  it('maps statuses', () => {
    expect(logStatusLabel('taken', false)).toBe('ทานแล้ว')
    expect(logStatusLabel('taken', true)).toBe('เลท')
    expect(logStatusLabel('skipped', false)).toBe('ยังไม่ได้ทาน')
    expect(logStatusLabel('pending', false)).toBe('ยังไม่บันทึก')
    expect(logStatusLabel('missed', true)).toBe('ยังไม่บันทึก')
  })
})

describe('planRowToView', () => {
  const row = {
    id: 'p1', medicine_id: 'm1', dose: '1 เม็ด', meal_relation: 'หลังอาหาร', start_date: '2026-01-01', end_date: '2026-01-31',
    status: 'active', doctor_note: 'ทานต่อเนื่อง',
    medicines: { generic_name: 'Paracetamol', trade_name: 'Tylenol' },
    medication_schedules: [{ time_of_day: '18:00:00' }, { time_of_day: '08:00:00' }],
  }
  it('maps a full row: trade name, sorted HH:mm times, range, status', () => {
    expect(planRowToView(row)).toEqual({
      id: 'p1', medicineId: 'm1', name: 'Tylenol', dose: '1 เม็ด', meal: 'หลังอาหาร', start: '2026-01-01', end: '2026-01-31',
      range: '2026-01-01 – 2026-01-31', times: ['08:00', '18:00'], note: 'ทานต่อเนื่อง', status: 'active', statusLabel: 'ใช้งาน',
    })
  })
  it('falls back to generic name when trade name missing', () => {
    expect(planRowToView({ ...row, medicines: { generic_name: 'Paracetamol', trade_name: null } }).name).toBe('Paracetamol')
    expect(planRowToView({ ...row, medicines: { generic_name: 'Paracetamol', trade_name: '' } }).name).toBe('Paracetamol')
  })
  it('handles null end date, null optional fields and stopped status', () => {
    const v = planRowToView({ ...row, end_date: null, meal_relation: null, doctor_note: null, status: 'stopped' })
    expect(v.range).toBe('2026-01-01 – ไม่กำหนดวันสิ้นสุด')
    expect(v.end).toBe('')
    expect(v.meal).toBe('')
    expect(v.note).toBe('')
    expect(v.statusLabel).toBe('หยุดแล้ว')
  })
  it('handles a plan without schedules or medicine', () => {
    expect(planRowToView({ ...row, medication_schedules: [] }).times).toEqual([])
    expect(planRowToView({ ...row, medicines: null, medication_schedules: null }).name).toBe('-')
  })
})

describe('plan form -> save_plan args', () => {
  const view = planRowToView({
    id: 'p1', medicine_id: 'm1', dose: '1 เม็ด', meal_relation: null, start_date: '2026-01-01', end_date: null,
    status: 'active', doctor_note: null, medicines: null, medication_schedules: [{ time_of_day: '08:00:00' }],
  })
  it('editing an active plan keeps it active and sends the plan id', () => {
    const a = planRpcArgs('pat', planToForm(view), ['08:00'])
    expect(a.p_status).toBe('active')
    expect(a.p_plan_id).toBe('p1')
    expect(a.p_patient_id).toBe('pat')
  })
  it('editing a stopped plan keeps it stopped', () => {
    expect(planRpcArgs('pat', planToForm({ ...view, status: 'stopped' }), ['08:00']).p_status).toBe('stopped')
  })
  it('a stop override wins', () => {
    expect(planRpcArgs('pat', planToForm(view), ['08:00'], 'stopped').p_status).toBe('stopped')
  })
  it('a new plan is active with no plan id; empty end/meal/note become null', () => {
    const a = planRpcArgs('pat', { ...planToForm(view), id: null, status: 'active' }, ['08:00'])
    expect(a.p_plan_id).toBeNull()
    expect(a.p_status).toBe('active')
    expect([a.p_end, a.p_meal_relation, a.p_note]).toEqual([null, null, null])
  })
})
