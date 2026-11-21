import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { once } from 'node:events'
import { createServer } from 'node:net'
import { setTimeout as delay } from 'node:timers/promises'
import { test } from 'node:test'

test('member settings preserve transactions and revoke credentials', { timeout: 30_000 }, async t => {
  const database = new URL(process.env.NUXT_DATABASE_URL ?? 'invalid:')
  assert.equal(database.hostname, '127.0.0.1')
  assert.equal(database.pathname, '/lifebuoy_test')
  const listener = createServer()
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve))
  const { port } = listener.address()
  await new Promise(resolve => listener.close(resolve))
  const base = `http://127.0.0.1:${port}/api/v1/`
  const server = spawn(process.execPath, ['.output/server/index.mjs'], {
    env: { ...process.env, NITRO_HOST: '127.0.0.1', NITRO_PORT: String(port) },
    stdio: ['ignore', 'ignore', 'pipe'],
  })
  const exited = once(server, 'exit')
  let logs = ''
  server.stderr.on('data', chunk => { logs = (logs + chunk).slice(-4000) })
  t.after(async () => {
    server.kill()
    await exited
  })
  let ready = false
  for (let i = 0; i < 80; i++) {
    const response = await fetch(base + 'home').catch(() => null)
    if (response?.status === 401) { ready = true; break }
    await delay(100)
  }
  assert.ok(ready, logs)

  async function call(path, body, token, status = 200) {
    const response = await fetch(base + path, {
      method: body == null ? 'GET' : 'POST',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
      body: body == null ? undefined : JSON.stringify(body),
    })
    const result = await response.json()
    assert.equal(response.status, status, JSON.stringify(result) + '\n' + logs)
    return result
  }

  const username = 'set_' + randomUUID().replaceAll('-', '').slice(0, 15)
  const password = 'original-' + randomUUID()
  const newPassword = 'replacement-' + randomUUID()
  const originalDistrict = 'hk-north'
  const nextDistrict = 'hk-tai-po'
  const oldPost = randomUUID()
  const newPost = randomUUID()
  const trade = randomUUID()
  const { token } = await call('auth/register', { username, password, name: '換區測試', community_id: originalDistrict })
  const { token: counterparty } = await call('auth/register', {
    username: username + '_other', password, name: '交易對方', community_id: originalDistrict,
  })
  await call('posts', { id: oldPost, kind: 'free', title: '舊區刊登', area: '驗收區' }, token)
  await call('posts', { id: trade, kind: 'request', title: '持續的互助', area: '驗收區', minutes: 20 }, token)
  await call(`posts/${trade}/match`, {}, counterparty)
  await call('account/profile', { name: '換區測試', community_id: 'demo' }, token, 400)
  await call('account/profile', { name: '新顯示名稱', community_id: nextDistrict, username: 'ignored' }, token)
  const moved = await call('home', null, token)
  assert.equal(moved.account.community_id, nextDistrict)
  assert.equal(moved.account.name, '新顯示名稱')
  assert.equal(moved.account.balance, 60)
  assert.ok(moved.services.some(service => service.id === trade))
  assert.ok(!(await call('board')).posts.some(post => post.id === oldPost))
  for (const action of ['agree', 'confirm']) {
    await call(`services/${trade}/${action}`, { minutes: 20 }, token)
    await call(`services/${trade}/${action}`, { minutes: 20 }, counterparty)
  }
  const settled = await call('home', null, token)
  assert.equal(settled.account.balance, 40)
  assert.ok(settled.entries.some(entry => entry.service_id === trade && entry.delta === -20))
  assert.equal(settled.entries.filter(entry => entry.kind === 'opening_credit').length, 1)
  await call('posts', { id: newPost, kind: 'free', title: '新區刊登', area: '驗收區' }, token)
  assert.equal((await call('board')).posts.find(post => post.id === newPost)?.community_id, nextDistrict)
  await call('account/profile', { name: '更名後返回', community_id: originalDistrict }, token)
  assert.equal((await call('home', null, token)).account.balance, 40)
  assert.ok(!(await call('board')).posts.some(post => post.id === oldPost || post.id === newPost))

  const { token: secondSession } = await call('auth/login', { username, password })
  await call('account/password', { current_password: 'wrong-password', new_password: newPassword }, token, 400)
  await call('account/password', { current_password: password, new_password: newPassword }, token)
  await call('home', null, token, 401)
  await call('home', null, secondSession, 401)
  await call('auth/login', { username, password }, undefined, 401)
  const { token: updated } = await call('auth/login', { username, password: newPassword })
  const remaining = randomUUID()
  await call('posts', { id: remaining, kind: 'request', title: '未完成互助', area: '驗收區', minutes: 10 }, updated)
  await call(`posts/${remaining}/match`, {}, counterparty)
  await call('account/delete', { current_password: newPassword }, updated)
  await call('home', null, updated, 401)
  await call('auth/login', { username, password: newPassword }, undefined, 401)
  const peer = await call('home', null, counterparty)
  assert.equal(peer.services.find(service => service.id === remaining)?.state, 'cancelled')
  assert.equal(peer.services.find(service => service.id === trade)?.state, 'settled')
  assert.ok(!peer.members.some(member => member.id === moved.account.id))
  assert.equal((await call('members/' + moved.account.id, null, counterparty)).name, '已刪除的用戶')
})
