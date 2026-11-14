import type { ReactNode } from 'react'
import * as D from './data'
import type { Tone } from './data'

export const tones: Record<Tone, string> = {
  green: 'bg-emerald-100 text-emerald-800 ring-emerald-300',
  yellow: 'bg-amber-100 text-amber-900 ring-amber-300',
  red: 'bg-red-100 text-red-800 ring-red-300',
  gray: 'bg-slate-100 text-slate-600 ring-slate-300',
}
export const dots: Record<Tone, string> = { green: 'bg-emerald-500', yellow: 'bg-amber-500', red: 'bg-red-500', gray: 'bg-slate-400' }
export const followLabel: Record<Tone, string> = { green: 'ปกติ', yellow: 'รอติดตาม', red: 'ต้องติดตาม', gray: 'ไม่มีข้อมูล' }
export const logTone: Record<string, Tone> = { ทานแล้ว: 'green', เลท: 'yellow', ข้าม: 'red', ยังไม่บันทึก: 'gray' }
export const apTone: Record<string, Tone> = { รอนัด: 'yellow', มาตามนัด: 'green', เลื่อนนัด: 'gray', ยกเลิก: 'red' }

export const pName = (id: string) => D.patients.find((p) => p.id === id)?.name ?? '-'
export const dName = (id: string) => D.doctors.find((d) => d.id === id)?.name ?? '-'
export const mName = (id: string) => D.medicines.find((m) => m.id === id)?.generic ?? '-'
export const fmt = (s: string) => new Date(s).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short' })

export function Badge({ tone, children }: { tone: Tone; children: ReactNode }) {
  return (
    <span className={`inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-3 py-1 text-sm font-medium ring-1 ${tones[tone]}`}>
      <span className={`size-2 rounded-full ${dots[tone]}`} />
      {children}
    </span>
  )
}
export const Card = ({ children, className = '' }: { children: ReactNode; className?: string }) => (
  <section className={`rounded-2xl border border-slate-200 bg-white p-5 shadow-sm ${className}`}>{children}</section>
)
export const H = ({ children, action }: { children: ReactNode; action?: ReactNode }) => (
  <div className="mb-4 flex items-center justify-between gap-3">
    <h2 className="text-lg font-semibold">{children}</h2>
    {action}
  </div>
)
export const Btn = ({ children, onClick, kind = 'primary', disabled }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'ghost' | 'danger'; disabled?: boolean }) => (
  <button
    onClick={onClick}
    disabled={disabled}
    type={onClick ? 'button' : 'submit'} // a button with a handler must not submit the surrounding form
    className={`min-h-11 rounded-xl px-4 text-base font-medium transition disabled:opacity-50 ${
      kind === 'primary' ? 'bg-brand-600 text-white hover:bg-brand-700' : kind === 'danger' ? 'border border-red-300 text-red-700 hover:bg-red-50' : 'border border-slate-300 hover:bg-slate-50'
    }`}
  >
    {children}
  </button>
)
export const inputCls = 'min-h-11 w-full rounded-xl border border-slate-300 bg-white px-3 text-base outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100'
export const Search = ({ v, set, ph = 'ค้นหา...' }: { v: string; set: (s: string) => void; ph?: string }) => (
  <input className={inputCls + ' sm:max-w-xs'} placeholder={ph} value={v} onChange={(e) => set(e.target.value)} />
)
export const Select = ({ v, set, opts, all }: { v: string; set: (s: string) => void; opts: [string, string][]; all: string }) => (
  <select className={inputCls + ' sm:w-auto'} value={v} onChange={(e) => set(e.target.value)}>
    <option value="">{all}</option>
    {opts.map(([k, l]) => (
      <option key={k} value={k}>{l}</option>
    ))}
  </select>
)
export function Table({ head, rows }: { head: string[]; rows: ReactNode[][] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] text-left text-base">
        <thead>
          <tr className="border-b border-slate-200 text-sm text-slate-500">
            {head.map((h) => (
              <th key={h} className="px-3 py-2 font-medium">{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
              {r.map((c, j) => (
                <td key={j} className="px-3 py-3 align-middle">{c}</td>
              ))}
            </tr>
          ))}
          {!rows.length && (
            <tr><td colSpan={head.length} className="px-3 py-8 text-center text-slate-400">ไม่พบข้อมูล</td></tr>
          )}
        </tbody>
      </table>
    </div>
  )
}
export const Stat = ({ label, value, tone }: { label: string; value: number; tone: Tone }) => (
  <Card>
    <div className="flex items-center gap-2 text-sm text-slate-500"><span className={`size-2.5 rounded-full ${dots[tone]}`} />{label}</div>
    <div className="mt-2 text-4xl font-bold text-brand-900">{value}</div>
  </Card>
)
export const Field = ({ label, children }: { label: string; children: ReactNode }) => (
  <label className="block text-sm font-medium text-slate-600">
    <span className="mb-1 block">{label}</span>
    {children}
  </label>
)
// The title is stored inside full_name ("นาย ธนพล ..."), like the names already saved. Not added twice if typed in the name too.
export const withTitle = (title: string, name: string) => {
  const n = name.trim()
  return title && n && !n.startsWith(title) ? `${title} ${n}` : n // empty name stays empty, so "required" checks still fire
}
export const TitleSelect = ({ v, set }: { v: string; set: (s: string) => void }) => (
  <Field label="คำนำหน้า">
    <select className={inputCls} value={v} onChange={(e) => set(e.target.value)}>
      <option value="">ไม่ระบุ</option>
      {['นาย', 'นาง', 'นางสาว', 'เด็กชาย', 'เด็กหญิง'].map((t) => <option key={t}>{t}</option>)}
    </select>
  </Field>
)
export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-0 sm:items-center sm:p-4" onClick={onClose}>
      <div className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-t-3xl bg-white p-6 sm:rounded-3xl" onClick={(e) => e.stopPropagation()}>
        <H action={<Btn kind="ghost" onClick={onClose}>ปิด</Btn>}>{title}</H>
        {children}
      </div>
    </div>
  )
}
