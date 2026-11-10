import { describe, expect, it } from 'vitest'
import { noticeRpcArgs, validateNotice } from './notices'

describe('validateNotice', () => {
  it('accepts a normal message', () => {
    expect(validateNotice('นัดตรวจ', 'พรุ่งนี้ 9 โมง')).toBeNull()
  })
  it('rejects empty or whitespace-only title and body', () => {
    expect(validateNotice('', 'b')).toBe('กรอกหัวข้อ')
    expect(validateNotice('   ', 'b')).toBe('กรอกหัวข้อ')
    expect(validateNotice('t', '')).toBe('กรอกข้อความ')
    expect(validateNotice('t', ' \n ')).toBe('กรอกข้อความ')
  })
  it('limits title to 100 and body to 500 characters (Thai counted per character)', () => {
    expect(validateNotice('ก'.repeat(100), 'b')).toBeNull()
    expect(validateNotice('ก'.repeat(101), 'b')).toBe('หัวข้อต้องไม่เกิน 100 ตัวอักษร')
    expect(validateNotice('t', 'ข'.repeat(500))).toBeNull()
    expect(validateNotice('t', 'ข'.repeat(501))).toBe('ข้อความต้องไม่เกิน 500 ตัวอักษร')
  })
  it('counts an emoji as one character, like the database', () => {
    expect(validateNotice('😀'.repeat(100), 'b')).toBeNull()
    expect(validateNotice('😀'.repeat(101), 'b')).toBe('หัวข้อต้องไม่เกิน 100 ตัวอักษร')
  })
  it('measures after trimming', () => {
    expect(validateNotice('  ' + 'ก'.repeat(100) + '  ', 'b')).toBeNull()
  })
})

describe('noticeRpcArgs', () => {
  it('trims and names the rpc parameters', () => {
    expect(noticeRpcArgs('pid', '  หัวข้อ ', ' ข้อความ\n')).toEqual({ p_patient_id: 'pid', p_title: 'หัวข้อ', p_body: 'ข้อความ' })
  })
})
