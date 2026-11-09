import { describe, expect, it } from 'vitest'
import { isHHmm, isThaiMobile, logStatusLabel, normalizeTimes, validatePlanForm } from './plans'

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
