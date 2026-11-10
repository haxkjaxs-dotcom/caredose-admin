// Same limits as send_notification in supabase/integration.sql; [...s] counts characters, not UTF-16 units, like char_length.
const len = (s: string) => [...s].length

export function validateNotice(title: string, body: string): string | null {
  const t = title.trim()
  const b = body.trim()
  if (!t) return 'กรอกหัวข้อ'
  if (len(t) > 100) return 'หัวข้อต้องไม่เกิน 100 ตัวอักษร'
  if (!b) return 'กรอกข้อความ'
  if (len(b) > 500) return 'ข้อความต้องไม่เกิน 500 ตัวอักษร'
  return null
}

export const noticeRpcArgs = (patientId: string, title: string, body: string) => ({
  p_patient_id: patientId, p_title: title.trim(), p_body: body.trim(),
})
