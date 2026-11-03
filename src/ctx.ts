import * as D from './data'
import type { Plan, Appt } from './data'

export type Role = 'Admin' | 'Doctor'
export type FollowUp = { id: string; patient: string; note: string; at: string; by: string }

export type Ctx = {
  patients: typeof D.patients; ids: Set<string>; plans: Plan[]; setPlans: (p: Plan[]) => void
  appts: Appt[]; setAppts: (a: Appt[]) => void; notify: (m: string) => void; role: Role
  followUps: FollowUp[]; setFollowUps: (items: FollowUp[]) => void
  openPatient: (id: string) => void; go: (p: string) => void
}
