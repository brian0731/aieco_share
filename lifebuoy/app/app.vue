<script setup lang="ts">
import type { DropdownMenuItem, NavigationMenuItem, TableColumn } from '@nuxt/ui'
import { displayValue, sections, statusKey, type AdminDashboard, type AdminRow, type SectionKey } from './utils/admin-display'

type Action = { label: string, subject: string, path: string, body: Record<string, string>, needsReason?: boolean }
type View = SectionKey | 'overview'
const token = ref('')
const dashboard = ref<AdminDashboard>()
const busy = ref(false)
const error = ref('')
const notice = ref('')
const view = ref<View>('overview')
const sidebarOpen = ref(false)
const query = ref('')
const page = ref(1)
const pendingAction = ref<Action>()
const actionOpen = ref(false)
const reason = ref('')
const record = ref<AdminRow>()
const recordOpen = ref(false)
const pageSize = 10
const keys = Object.keys(sections) as SectionKey[]
const section = computed(() => view.value === 'overview' ? null : view.value)
const title = computed(() => section.value ? sections[section.value].label : '總覽')

function navigate(next: View) {
  view.value = next
  query.value = ''
  sidebarOpen.value = false
}

const navigation = computed<NavigationMenuItem[]>(() => [
  { label: '總覽', icon: 'i-lucide-layout-dashboard', active: view.value === 'overview', onSelect: () => navigate('overview') },
  ...keys.map(key => ({
    label: sections[key].label, icon: sections[key].icon, active: view.value === key, onSelect: () => navigate(key),
  })),
])

const columns = computed<TableColumn<AdminRow>[]>(() => {
  const key = section.value
  if (!key) return []
  return [
    ...sections[key].columns.map(([field, header]) => ({
      id: field, header, accessorFn: (row: AdminRow) => displayValue(key, row, field),
    })),
    { id: 'actions', header: '操作' },
  ]
})

const results = computed(() => {
  const key = section.value
  if (!key || !dashboard.value) return []
  const words = query.value.toLowerCase().trim().split(/\s+/).filter(Boolean)
  return dashboard.value[key].filter((row) => {
    const text = sections[key].columns.map(([field]) => displayValue(key, row, field)).join(' ').toLowerCase()
    return words.every(word => text.includes(word))
  })
})
const visibleRows = computed(() => results.value.slice((page.value - 1) * pageSize, page.value * pageSize))
const openDisputes = computed(() => dashboard.value?.disputes.filter(row => !row.outcome) ?? [])
const summary = computed(() => {
  const data = dashboard.value
  if (!data) return []
  return [
    { title: '待處理申訴', amount: openDisputes.value.length, icon: sections.disputes.icon, to: 'disputes' },
    { title: '進行中服務', amount: data.services.filter(row => ['agreement', 'pending'].includes(String(row.state))).length, icon: sections.services.icon, to: 'services' },
    { title: '保留中交收', amount: data.exchanges.filter(row => statusKey('exchanges', row) === 'reserved').length, icon: sections.exchanges.icon, to: 'exchanges' },
    { title: '成員', amount: data.members.length, icon: sections.members.icon, to: 'members' },
  ] as const
})

watch(query, () => { page.value = 1 })
watch(view, () => { page.value = 1 })
watch(results, value => { page.value = Math.min(page.value, Math.max(1, Math.ceil(value.length / pageSize))) })

async function call<T>(path: string, body?: Record<string, string>) {
  return $fetch<T>('/api/v1/' + path, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + token.value.trim() },
    body,
  })
}

const errorText: Record<string, string> = {
  invalid_token: '登入識別碼無效或已過期。',
  token_required: '請輸入有效的管理員登入識別碼。',
  admin_required: '此帳戶沒有管理權限。',
  insufficient_balance: '會員餘額不足以執行相抵更正。',
  invalid_transition: '紀錄狀態已變更，請更新後重試。',
  retry_transaction: '資料正在更新，請稍後重試。',
}

async function load(action?: Action) {
  if (busy.value) return
  busy.value = true
  error.value = ''
  notice.value = ''
  let saved = false
  try {
    if (action) {
      await call(action.path, { ...action.body, ...(action.needsReason ? { reason: reason.value.trim() } : {}) })
      saved = true
      actionOpen.value = false
    }
    dashboard.value = await call<AdminDashboard>('admin')
    if (saved) notice.value = '已儲存並更新紀錄。'
  } catch (problem) {
    const response = problem as { statusCode?: number, data?: { statusMessage?: string } }
    const status = response.data?.statusMessage ?? ''
    error.value = saved ? '已儲存，暫時無法更新列表。' : errorText[status] ?? '暫時無法完成，請稍後重試。'
    if (response.statusCode === 401 || response.statusCode === 403) dashboard.value = undefined
  } finally {
    busy.value = false
  }
}

function prepare(action: Action) {
  pendingAction.value = action
  reason.value = ''
  error.value = ''
  actionOpen.value = true
}

function actions(key: SectionKey, row: AdminRow): DropdownMenuItem[] {
  const items: DropdownMenuItem[] = [{
    label: '查看詳情', icon: 'i-lucide-file-text', onSelect: () => { record.value = row; recordOpen.value = true },
  }]
  if (key === 'disputes') {
    const collection = row.kind === 'service' ? 'services' : 'exchanges'
    const path = `${collection}/${row.trade_id}/resolve`
    const subject = displayValue(key, row, 'trade_title')
    for (const [outcome, label] of [['restore', '恢復評價'], ['exclude', '排除評價']] as const) {
      items.push({ label, onSelect: () => prepare({ label, subject, path, body: { outcome }, needsReason: true }) })
    }
  }
  if (key === 'services' && row.state === 'settled') {
    items.push({ label: '相抵更正', icon: 'i-lucide-rotate-ccw', onSelect: () => prepare({
      label: '相抵更正', subject: displayValue(key, row, 'title'),
      path: `services/${row.id}/reverse`, body: {}, needsReason: true,
    }) })
  }
  if (key === 'exchanges' && statusKey(key, row) === 'expired') {
    items.push({ label: '釋出逾期保留', icon: 'i-lucide-unlock', onSelect: () => prepare({
      label: '釋出逾期保留', subject: `${row.offered_title ?? '—'} ⇄ ${row.wanted_title ?? '—'}`,
      path: `exchanges/${row.id}/expire`, body: {},
    }) })
  }
  return items
}

function badge(key: SectionKey, row: AdminRow) {
  const status = statusKey(key, row)
  if (['unresolved', 'expired', 'agreement', 'pending', 'proposed'].includes(status)) return 'warning'
  if (['completed', 'settled', 'restore', 'available'].includes(status)) return 'success'
  return 'neutral'
}

function signOut() {
  dashboard.value = undefined
  token.value = ''
  error.value = ''
  notice.value = ''
  recordOpen.value = false
  actionOpen.value = false
  navigate('overview')
}

useHead({ title: '社區救生圈管理', htmlAttrs: { lang: 'zh-Hant-HK' } })
</script>

<template>
  <UApp>
    <main v-if="!dashboard" class="min-h-dvh bg-muted px-5 py-12 sm:grid sm:place-items-center">
      <UCard class="mx-auto w-full max-w-sm">
        <div class="mb-7 flex items-center gap-3">
          <span class="grid size-10 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
            <UIcon name="i-lucide-life-buoy" class="size-5" />
          </span>
          <h1 class="text-xl font-semibold">社區救生圈管理</h1>
        </div>
        <form class="space-y-4" @submit.prevent="load()">
          <UFormField label="管理員登入識別碼">
            <UInput v-model="token" icon="i-lucide-key-round" type="password" autocomplete="off" required class="w-full" />
          </UFormField>
          <UAlert v-if="error" color="error" variant="soft" :title="error" />
          <UButton type="submit" block :loading="busy" :disabled="!token.trim()" label="登入" />
        </form>
      </UCard>
    </main>

    <UDashboardGroup v-else unit="rem">
      <UDashboardSidebar v-model:open="sidebarOpen" :default-size="15" :ui="{ body: 'pt-3' }">
        <template #header>
          <div class="flex min-w-0 items-center gap-3">
            <span class="grid size-9 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
              <UIcon name="i-lucide-life-buoy" class="size-5" />
            </span>
            <div class="min-w-0">
              <p class="font-semibold">社區救生圈管理</p>
              <p class="truncate text-xs text-muted">{{ dashboard.community || '管理社區' }}</p>
            </div>
          </div>
        </template>
        <UNavigationMenu :items="navigation" orientation="vertical" />
      </UDashboardSidebar>

      <UDashboardPanel :ui="{ body: 'bg-muted/40 gap-6' }">
        <template #header>
          <UDashboardNavbar :title="title">
            <template #leading><UDashboardSidebarToggle /></template>
            <template #right>
              <UButton icon="i-lucide-refresh-cw" label="更新" color="neutral" variant="ghost" :loading="busy" @click="load()" />
              <UButton icon="i-lucide-log-out" label="登出" color="neutral" variant="ghost" :disabled="busy" @click="signOut" />
            </template>
          </UDashboardNavbar>
        </template>

        <template #body>
          <UAlert v-if="error && !actionOpen" color="error" variant="soft" :title="error" />
          <UAlert v-if="notice" color="success" variant="soft" :title="notice" />

          <template v-if="!section">
            <section aria-label="社區總覽" class="grid grid-cols-2 divide-default rounded-lg border border-default bg-default xl:grid-cols-4 xl:divide-x">
              <button v-for="card in summary" :key="card.to" type="button"
                class="flex items-start gap-3 p-4 text-left hover:bg-elevated/50 sm:p-5"
                @click="navigate(card.to)">
                <UIcon :name="card.icon" class="mt-0.5 size-5 shrink-0 text-primary" />
                <span>
                  <span class="block text-sm text-muted">{{ card.title }}</span>
                  <span class="mt-1 block text-2xl font-semibold tabular-nums">{{ card.amount }}</span>
                </span>
              </button>
            </section>
            <section aria-labelledby="open-disputes" class="rounded-lg border border-default bg-default">
              <div class="flex items-center justify-between gap-4 border-b border-default px-4 py-3 sm:px-5">
                <h2 id="open-disputes" class="font-semibold">待處理申訴</h2>
                <UButton label="查看申訴" icon="i-lucide-arrow-right" trailing variant="ghost" @click="navigate('disputes')" />
              </div>
              <ul v-if="openDisputes.length" class="divide-y divide-default">
                <li v-for="row in openDisputes.slice(0, 5)" :key="String(row.kind) + row.trade_id"
                  class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-5">
                  <span class="min-w-0 wrap-break-word">
                    <span class="block font-medium">{{ displayValue('disputes', row, 'trade_title') }}</span>
                    <span class="text-sm text-muted">{{ displayValue('disputes', row, 'reporter_name') }} · {{ displayValue('disputes', row, 'created_at') }}</span>
                  </span>
                  <UBadge color="warning" variant="soft" label="待處理" />
                </li>
              </ul>
              <p v-else class="px-4 py-7 text-sm text-muted sm:px-5">目前沒有待處理申訴</p>
            </section>
          </template>

          <section v-else class="min-w-0 overflow-hidden rounded-lg border border-default bg-default" :aria-label="title">
            <div class="flex flex-wrap items-center justify-between gap-3 border-b border-default px-4 py-3">
              <UInput v-model="query" icon="i-lucide-search" :placeholder="'搜尋' + title" :aria-label="'搜尋' + title" class="w-full sm:max-w-xs" />
              <span class="text-sm tabular-nums text-muted">{{ results.length }} 筆{{ dashboard[section].length === 100 ? ' · 已載入上限 100 筆' : '' }}</span>
            </div>
            <UTable :key="section" :data="visibleRows" :columns="columns" :empty="query.trim() ? '找不到符合的紀錄' : '目前沒有紀錄'"
              :ui="{ td: 'align-top max-w-72 whitespace-normal wrap-break-word' }">
              <template #state-cell="{ row }">
                <UBadge :color="badge(section, row.original)" variant="soft" :label="displayValue(section, row.original, 'state')" />
              </template>
              <template #outcome-cell="{ row }">
                <UBadge :color="badge(section, row.original)" variant="soft" :label="displayValue(section, row.original, 'outcome')" />
              </template>
              <template #actions-cell="{ row }">
                <UDropdownMenu :items="actions(section, row.original)" :content="{ align: 'end' }">
                  <UButton icon="i-lucide-ellipsis" color="neutral" variant="ghost" aria-label="紀錄操作" />
                </UDropdownMenu>
              </template>
            </UTable>
            <div v-if="results.length > pageSize" class="flex justify-end border-t border-default p-3">
              <UPagination v-model:page="page" :items-per-page="pageSize" :total="results.length" :sibling-count="0" />
            </div>
          </section>
        </template>
      </UDashboardPanel>
    </UDashboardGroup>

    <UModal v-model:open="recordOpen" :title="(section ? sections[section].label : '') + '詳情'">
      <template #body>
        <dl v-if="section && record" class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-3 text-sm">
          <template v-for="[key, label] in sections[section].columns" :key="key">
            <dt class="text-muted">{{ label }}</dt>
            <dd class="wrap-break-word">{{ displayValue(section, record, key) }}</dd>
          </template>
          <template v-if="record.resolution_reason">
            <dt class="text-muted">處理原因</dt><dd class="wrap-break-word">{{ record.resolution_reason }}</dd>
          </template>
          <template v-if="record.trade_id || record.service_id || record.id">
            <dt class="text-muted">參考編號</dt><dd class="font-mono text-xs wrap-break-word">{{ record.trade_id || record.service_id || record.id }}</dd>
          </template>
        </dl>
      </template>
    </UModal>

    <UModal v-model:open="actionOpen" :title="pendingAction?.label ?? '確認操作'" :description="pendingAction?.subject" :dismissible="!busy">
      <template #body>
        <form v-if="pendingAction" class="space-y-4" @submit.prevent="load(pendingAction)">
          <UFormField v-if="pendingAction.needsReason" label="處理原因" required>
            <UTextarea v-model="reason" maxlength="500" required autofocus class="w-full" />
          </UFormField>
          <p v-else class="text-sm text-muted">確認釋出這筆交收的物品保留？</p>
          <UAlert v-if="error" color="error" variant="soft" :title="error" />
          <div class="flex justify-end gap-2">
            <UButton label="取消" color="neutral" variant="outline" :disabled="busy" @click="actionOpen = false" />
            <UButton type="submit" label="確認" :loading="busy" :disabled="pendingAction.needsReason && !reason.trim()" />
          </div>
        </form>
      </template>
    </UModal>
  </UApp>
</template>
