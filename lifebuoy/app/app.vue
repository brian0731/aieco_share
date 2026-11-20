<script setup lang="ts">
type Row = Record<string, string | number | null>
type Dashboard = Record<string, Row[]>
const token = ref('')
const dashboard = ref<Dashboard>()
const busy = ref(false)
const message = ref('')
const reason = ref('')
const section = ref('disputes')
const labels: Record<string, string> = {
  disputes: '申訴', services: '服務配對', ledger: '時間帳本', members: '成員',
  items: '物資', exchanges: '交收', audit: '稽核',
}
async function call(path: string, body?: Record<string, string>) {
  return $fetch('/api/v1/' + path, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + token.value.trim() },
    body,
  })
}
async function load(action?: string, body?: Record<string, string>) {
  busy.value = true
  message.value = ''
  try {
    if (action) await call(action, body)
    dashboard.value = await call('admin') as Dashboard
    if (action) {
      reason.value = ''
      message.value = '已儲存'
    }
  } catch (error) {
    const problem = error as { data?: { statusMessage?: string } }
    message.value = '操作未完成 · ' + (problem.data?.statusMessage ?? '連線失敗')
    if (!action) dashboard.value = undefined
  } finally {
    busy.value = false
  }
}
function resolve(row: Row, outcome: string) {
  const collection = row.kind === 'service' ? 'services' : 'exchanges'
  return load(collection + '/' + row.trade_id + '/resolve', { outcome, reason: reason.value })
}
function signOut() {
  dashboard.value = undefined
  token.value = ''
  reason.value = ''
  message.value = ''
}
useHead({ title: '社區救生圈管理', htmlAttrs: { lang: 'zh-Hant' } })
</script>

<template>
  <main>
    <header>
      <h1>社區救生圈管理</h1>
      <button v-if="dashboard" :disabled="busy" @click="signOut">登出</button>
    </header>
    <form v-if="!dashboard" @submit.prevent="load()">
      <label>管理員登入識別碼 <input v-model="token" type="password" required autocomplete="off"></label>
      <button :disabled="busy">登入</button>
    </form>
    <p v-if="message" role="status">{{ message }}</p>
    <template v-if="dashboard">
      <nav aria-label="管理項目">
        <button v-for="(label,key) in labels" :key="key"
          :aria-pressed="section === key" @click="section = key">{{ label }}</button>
        <button :disabled="busy" @click="load()">更新</button>
      </nav>
      <h2>{{ labels[section] }}</h2>
      <label v-if="section === 'disputes' || section === 'services'">處理原因
        <input v-model="reason" maxlength="500">
      </label>
      <p v-if="!dashboard[section]?.length">沒有紀錄</p>
      <div v-else class="table">
        <table>
          <thead><tr>
            <th v-for="(_,key) in dashboard[section]?.[0]" :key="key" scope="col">{{ key }}</th>
            <th v-if="['disputes','services','exchanges'].includes(section)" scope="col">操作</th>
          </tr></thead>
          <tbody>
            <tr v-for="(row,index) in dashboard[section]" :key="index">
              <td v-for="(value,key) in row" :key="key">{{ value ?? '—' }}</td>
              <td v-if="section === 'disputes'" class="actions">
                <button :disabled="busy || !reason.trim()" @click="resolve(row,'restore')">恢復評價</button>
                <button :disabled="busy || !reason.trim()" @click="resolve(row,'exclude')">排除評價</button>
              </td>
              <td v-else-if="section === 'services'">
                <button v-if="row.state === 'settled'" :disabled="busy || !reason.trim()"
                  @click="load('services/'+row.id+'/reverse', { reason })">相抵更正</button>
              </td>
              <td v-else-if="section === 'exchanges'">
                <button v-if="row.state === 'reserved'" :disabled="busy"
                  @click="load('exchanges/'+row.id+'/expire', {})">釋出逾期保留</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </main>
</template>

<style>
:root { font-family: system-ui,sans-serif; color: #182c28; background: #f6f8f6; }
main { max-width: 1260px; margin: 0 auto; padding: 24px; }
header, nav, form { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
header { justify-content: space-between; }
h1 { font-size: 1.6rem; }
h2 { font-size: 1.15rem; }
button, input { font: inherit; border: 1px solid #8a9a92; border-radius: 5px; padding: 8px 12px; }
button { background: white; color: inherit; cursor: pointer; }
button[aria-pressed=true] { background: #075c51; color: white; }
button:disabled { opacity: .5; cursor: default; }
input { max-width: 100%; box-sizing: border-box; }
.table { margin-top: 16px; overflow: auto; }
table { background: white; width: 100%; border-collapse: collapse; text-align: left; font-size: .9rem; }
th, td { border-bottom: 1px solid #d7e0db; padding: 9px; overflow-wrap: anywhere; }
th { background: #e8efec; }
.actions { min-width: 110px; }
.actions button + button { margin-top: 6px; }
</style>
