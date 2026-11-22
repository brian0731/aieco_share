export type AdminRow = Record<string, string | number | boolean | null | undefined>
type Column = [key: string, label: string]
type Section = { label: string, icon: string, columns: Column[] }

export const sections = {
  reports: { label: '內容舉報', icon: 'i-lucide-flag', columns: [
    ['kind', '內容類型'], ['target_name', '發佈者'], ['district', '地區'],
    ['reason', '舉報原因'], ['reporter_name', '舉報人'], ['state', '狀態'], ['created_at', '舉報時間'],
  ] },
  disputes: { label: '申訴', icon: 'i-lucide-message-square-warning', columns: [
    ['trade_title', '涉及事項'], ['reporter_name', '申訴人'], ['kind', '類型'],
    ['reason', '申訴理由'], ['outcome', '處理狀態'], ['created_at', '提出時間'],
  ] },
  members: { label: '成員', icon: 'i-lucide-users', columns: [
    ['name', '顯示名稱'], ['username', '使用者名稱'], ['district', '地區'], ['role', '角色'], ['balance', '可用時間'],
  ] },
  services: { label: '服務配對', icon: 'i-lucide-hand-heart', columns: [
    ['title', '服務'], ['provider_name', '協助者'], ['payer_name', '受助者'],
    ['area', '地點'], ['minutes', '時數'], ['state', '狀態'], ['completed_at', '完成時間'],
  ] },
  ledger: { label: '時間帳本', icon: 'i-lucide-notebook-pen', columns: [
    ['title', '服務'], ['kind', '帳務類型'], ['minutes', '時數'], ['actor_name', '經手人'],
    ['reason', '原因'], ['created_at', '入帳時間'],
  ] },
  items: { label: '物資', icon: 'i-lucide-package', columns: [
    ['title', '物品'], ['wanted', '想換物品'], ['owner_name', '物主'], ['area', '地點'],
    ['state', '狀態'], ['created_at', '刊登時間'],
  ] },
  exchanges: { label: '交收', icon: 'i-lucide-arrow-left-right', columns: [
    ['offered_title', '提供物品'], ['wanted_title', '想換物品'], ['proposer_name', '提議人'],
    ['owner_name', '物主'], ['meeting', '交收地點'], ['state', '狀態'], ['expires_at', '保留至'],
  ] },
  audit: { label: '稽核', icon: 'i-lucide-history', columns: [
    ['action', '操作'], ['target_title', '涉及事項'], ['actor_name', '經手人'],
    ['reason', '原因'], ['created_at', '操作時間'],
  ] },
} satisfies Record<string, Section>

export type SectionKey = keyof typeof sections
export type AdminDashboard = Record<SectionKey, AdminRow[]> & {
  community?: string
  districts: { id: string, name: string, count: number }[]
}
export type AdminMemberPage = { members: AdminRow[], total: number, page: number }

const statuses: Record<string, string> = {
  agreement: '待同意時數', pending: '待確認完成', settled: '已入帳', cancelled: '已取消',
  reversed: '已相抵', proposed: '待接受', reserved: '保留中', expired: '保留已逾期',
  completed: '已完成', available: '可交換', restore: '已恢復評價', exclude: '已排除評價',
  unresolved: '待處理', member: '會員', admin: '管理員', settlement: '服務入帳',
  reversal: '相抵更正', service: '服務', exchange: '物品交收',
  post: '互助貼文', item: '交換刊登', chat: '光網訊息', dismissed: '已駁回', removed: '已下架',
}

const auditLabels: Record<string, string> = {
  match_service: '建立服務配對', agree_service: '同意服務時數', confirm_service: '確認服務完成',
  settle_service: '服務入帳', cancel_service: '取消服務', reverse_service: '相抵更正',
  propose_exchange: '提出交換', accept_exchange: '接受交換', handoff_exchange: '確認交收',
  cancel_exchange: '取消交換', expire_exchange: '釋出逾期保留',
  service_dispute_open: '提出服務申訴', exchange_dispute_open: '提出交收申訴',
  service_dispute_restore: '恢復服務評價', exchange_dispute_restore: '恢復交收評價',
  service_dispute_exclude: '排除服務評價', exchange_dispute_exclude: '排除交收評價',
  content_report_removed: '下架遭舉報內容', content_report_dismissed: '駁回內容舉報',
}

const date = new Intl.DateTimeFormat('zh-HK', {
  timeZone: 'Asia/Hong_Kong', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
})

export function statusKey(section: SectionKey, row: AdminRow) {
  if (section === 'items') return Number(row.exchanged) ? 'completed' : row.reserved_by ? 'reserved' : 'available'
  if (section === 'disputes') return String(row.outcome ?? 'unresolved')
  if (section === 'exchanges' && row.state === 'reserved' && Number(row.expired)) return 'expired'
  return String(row.state ?? '')
}

export function displayValue(section: SectionKey, row: AdminRow, key: string) {
  const value = row[key]
  if (section === 'reports' && key === 'state' && value === 'pending') return '待處理'
  if (key === 'state' || key === 'outcome') return statuses[statusKey(section, row)] ?? '未知狀態'
  if (value == null || value === '') return '—'
  if (key === 'role' || key === 'kind') return statuses[String(value)] ?? '未知類型'
  if (key === 'action') return auditLabels[String(value)] ?? '其他操作'
  if (key === 'balance' || key === 'minutes') return `${value} 分鐘`
  if (key.endsWith('_at')) {
    const parsed = new Date(String(value))
    return Number.isNaN(parsed.getTime()) ? '—' : date.format(parsed)
  }
  return String(value)
}
