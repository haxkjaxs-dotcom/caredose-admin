export type Tone = 'green' | 'yellow' | 'red' | 'gray'

// Mock data removed. These pages show empty until they are wired to Supabase (คลังยา and ผู้ใช้ already are).
export type Doctor = { id: string; name: string; dept: string; spec: string; phone: string; active: boolean }
export type Patient = { id: string; name: string; age: number; sex: string; conditions: string; allergy: string; doctor: string; caregivers: string[]; plan: string; follow: string; bmi: number }
export type Caregiver = { id: string; name: string; phone: string; rel: string; perm: string }
export type Medicine = { id: string; generic: string; brand: string; form: string; dose: string; unit: string; usage: string; warn: string; stock: number; active: boolean }
export type Plan = { id: string; patient: string; med: string; dose: string; qty: string; times: string[]; start: string; end: string; advice: string; note: string }
export type LogStatus = 'ทานแล้ว' | 'เลท' | 'ข้าม' | 'ยังไม่บันทึก'
export type Log = { id: string; at: string; patient: string; med: string; meal: string; status: LogStatus; by: string; note: string }
export type Appt = { id: string; patient: string; doctor: string; at: string; place: string; reason: string; note: string; status: 'รอนัด' | 'มาตามนัด' | 'เลื่อนนัด' | 'ยกเลิก' }

export const doctors: Doctor[] = []
export const patients: Patient[] = []
export const caregivers: Caregiver[] = []
export const medicines: Medicine[] = []
export const plans: Plan[] = []
export const logs: Log[] = []
export const appts: Appt[] = []
