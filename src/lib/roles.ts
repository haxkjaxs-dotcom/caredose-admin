import type { Role } from '../ctx'

export const roleFromRoles = (roles: string[], isActive: boolean): Role | 'none' =>
  !isActive ? 'none' : roles.includes('admin') ? 'Admin' : roles.includes('doctor') ? 'Doctor' : roles.includes('caregiver') ? 'Caregiver' : 'none'

export const canEditPlans = (role: Role) => role === 'Admin' || role === 'Doctor'

const CAREGIVER_PAGES = ['patients', 'plans', 'logs']
export const navIdsFor = (role: Role, all: { id: string; admin?: boolean }[]) =>
  all.filter((n) => (role === 'Caregiver' ? CAREGIVER_PAGES.includes(n.id) : role === 'Admin' || !n.admin)).map((n) => n.id)

export const defaultPageFor = (role: Role) => (role === 'Caregiver' ? 'patients' : 'dash')
