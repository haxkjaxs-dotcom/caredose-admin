import { describe, expect, it } from 'vitest'
import { canEditPlans, defaultPageFor, navIdsFor, roleFromRoles } from './roles'

describe('roleFromRoles', () => {
  it('maps a single role', () => {
    expect(roleFromRoles(['admin'], true)).toBe('Admin')
    expect(roleFromRoles(['doctor'], true)).toBe('Doctor')
    expect(roleFromRoles(['caregiver'], true)).toBe('Caregiver')
  })
  it('picks admin > doctor > caregiver', () => {
    expect(roleFromRoles(['caregiver', 'doctor', 'admin'], true)).toBe('Admin')
    expect(roleFromRoles(['caregiver', 'doctor'], true)).toBe('Doctor')
  })
  it('inactive account has no access', () => {
    expect(roleFromRoles(['admin'], false)).toBe('none')
    expect(roleFromRoles(['caregiver'], false)).toBe('none')
  })
  it('unknown or empty roles have no access', () => {
    expect(roleFromRoles(['patient'], true)).toBe('none')
    expect(roleFromRoles([], true)).toBe('none')
  })
})

describe('canEditPlans', () => {
  it('only Admin and Doctor', () => {
    expect(canEditPlans('Admin')).toBe(true)
    expect(canEditPlans('Doctor')).toBe(true)
    expect(canEditPlans('Caregiver')).toBe(false)
  })
})

const all = [{ id: 'dash' }, { id: 'patients' }, { id: 'plans' }, { id: 'logs' }, { id: 'appts' }, { id: 'users', admin: true }]
describe('navIdsFor', () => {
  it('Admin sees everything', () => expect(navIdsFor('Admin', all)).toEqual(['dash', 'patients', 'plans', 'logs', 'appts', 'users']))
  it('Doctor sees all but admin-only', () => expect(navIdsFor('Doctor', all)).toEqual(['dash', 'patients', 'plans', 'logs', 'appts']))
  it('Caregiver sees only patients, plans, logs', () => expect(navIdsFor('Caregiver', all)).toEqual(['patients', 'plans', 'logs']))
})

describe('defaultPageFor', () => {
  it('dash for Admin/Doctor, patients for Caregiver', () => {
    expect(defaultPageFor('Admin')).toBe('dash')
    expect(defaultPageFor('Doctor')).toBe('dash')
    expect(defaultPageFor('Caregiver')).toBe('patients')
  })
})
