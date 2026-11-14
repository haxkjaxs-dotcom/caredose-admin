import { describe, expect, it } from 'vitest'
import { withTitle } from '../ui'

describe('withTitle', () => {
  it('puts the title before the name', () => expect(withTitle('นาย', ' ธนพล เจริญรุ่งเรือง ')).toBe('นาย ธนพล เจริญรุ่งเรือง'))
  it('keeps the name when no title is chosen', () => expect(withTitle('', 'ธนพล')).toBe('ธนพล'))
  it('does not add a title typed in the name already', () => expect(withTitle('นาง', 'นาง สมหญิง')).toBe('นาง สมหญิง'))
  it('keeps an empty name empty', () => expect(withTitle('นาย', '  ')).toBe(''))
})

describe('withTitle, child titles', () => {
  it('adds เด็กหญิง', () => expect(withTitle('เด็กหญิง', 'มะลิ ใจดี')).toBe('เด็กหญิง มะลิ ใจดี'))
})
