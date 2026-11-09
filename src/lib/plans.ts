export const isThaiMobile = (s: string) => /^0[689]\d{8}$/.test(s.replace(/[\s-]/g, ''))

export const isHHmm = (s: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(s)

export const normalizeTimes = (list: string[]) => [...new Set(list.map((t) => t.trim()).filter(Boolean))].sort()

export function validatePlanForm(f: { medicineId: string; dose: string; start: string; end: string; times: string[] }): string | null {
  if (!f.medicineId) return 'เลือกยา'
  if (!f.dose.trim()) return 'กรอกขนาดยา'
  if (!f.start) return 'กรอกวันเริ่ม'
  if (f.end && f.end < f.start) return 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม' // ISO yyyy-mm-dd compares lexically
  if (f.times.length === 0 || !f.times.every(isHHmm)) return 'เพิ่มเวลาทานอย่างน้อย 1 เวลา (รูป HH:mm)'
  return null
}

export function logStatusLabel(status: 'pending' | 'taken' | 'skipped' | 'missed', isLate: boolean): string {
  if (status === 'taken') return isLate ? 'เลท' : 'ทานแล้ว'
  if (status === 'skipped') return 'ยังไม่ได้ทาน'
  return 'ยังไม่บันทึก'
}
