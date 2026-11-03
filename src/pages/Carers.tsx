import * as D from '../data'
import { Badge, Card, H, Table } from '../ui'
import type { Ctx } from '../ctx'

export function Carers({ ids }: Ctx) {
  return (
    <Card>
      <H>ญาติและผู้ดูแล</H>
      <Table
        head={['ชื่อ-นามสกุล', 'เบอร์โทร', 'ความสัมพันธ์', 'ผู้ป่วยที่ดูแล', 'สิทธิ์']}
        rows={D.caregivers.map((c) => [<b>{c.name}</b>, c.phone, c.rel, D.patients.filter((p) => p.caregivers.includes(c.id) && ids.has(p.id)).map((p) => p.name).join(', ') || '-', <Badge tone={c.perm === 'ดูอย่างเดียว' ? 'gray' : 'green'}>{c.perm}</Badge>])}
      />
    </Card>
  )
}
