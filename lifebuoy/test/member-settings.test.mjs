import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createHash, randomUUID } from 'node:crypto'
import { once } from 'node:events'
import { createServer } from 'node:net'
import { setTimeout as delay } from 'node:timers/promises'
import { test } from 'node:test'
import mysql from 'mysql2/promise'

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
  const db = await mysql.createConnection(database.href)
  t.after(() => db.end())
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
  const item = randomUUID()
  await call('items', { id: item, title: '私人物品說明', wanted: '繪本', area: '私密地點' }, updated)
  await call('reports', { kind: 'item', target_id: item, community_id: originalDistrict, reason: '原文副本' }, counterparty)
  await call(`services/${trade}/rate`, { stars: 5 }, updated)
  const chat = { message_id: randomUUID(), text: '會員私人訊息' }
  const { sender_id: senderId } = await call('chat/messages', chat, updated)
  assert.equal((await call('chat/messages', chat, updated)).sender_id, senderId)
  await call('chat/messages', { ...chat, text: '其他內容' }, updated, 409)
  const senderKey = createHash('sha256').update(senderId).digest('hex')
  async function openChatSocket() {
    const socket = new WebSocket('ws://127.0.0.1:' + port + '/ws/light')
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true })
      socket.addEventListener('error', reject, { once: true })
    })
    t.after(() => socket.close())
    return socket
  }
  const receiver = await openChatSocket()
  const sender = await openChatSocket()
  const received = []
  receiver.addEventListener('message', event => received.push(JSON.parse(event.data)))
  const packet = { kind: 'aieco.light.chat.v1', messageId: chat.message_id, senderId, text: chat.text }
  async function expectDelivery(message, expected) {
    received.length = 0
    sender.send(JSON.stringify(message))
    const marker = { ...packet, senderId: 'relay-probe', messageId: randomUUID(), text: '連線測試' }
    sender.send(JSON.stringify(marker))
    for (let attempt = 0; attempt < 60; attempt++) {
      if (received.some(entry => entry.messageId === marker.messageId) &&
          (!expected || received.some(entry => entry.messageId === message.messageId))) break
      await delay(25)
    }
    assert.ok(received.some(entry => entry.messageId === marker.messageId), logs)
    if (!expected) await delay(150)
    assert.equal(received.some(entry => entry.messageId === message.messageId), expected)
  }
  await expectDelivery({ ...packet, text: '未授權文字' }, false)
  await expectDelivery(packet, true)
  await call('reports', { kind: 'chat', target_id: chat.message_id, content: chat.text, sender_id: senderId,
    sender_name: '舊名稱', reason: '聊天室原文副本' }, counterparty)
  assert.deepEqual((await call('moderation/chat', { keys: [], senders: [senderKey] })).removed_senders, [])
  const remaining = randomUUID()
  await call('posts', { id: remaining, kind: 'request', title: '未完成互助', area: '驗收區', minutes: 10 }, updated)
  await call(`posts/${remaining}/match`, {}, counterparty)
  await call('account/delete', { current_password: newPassword }, updated)
  await call('home', null, updated, 401)
  await call('chat/messages', { ...chat, message_id: randomUUID() }, updated, 401)
  await call('auth/login', { username, password: newPassword }, undefined, 401)
  const peer = await call('home', null, counterparty)
  assert.equal(peer.services.find(service => service.id === remaining)?.state, 'cancelled')
  const completed = peer.services.find(service => service.id === trade)
  assert.equal(completed?.state, 'settled')
  assert.equal(completed?.title, '已刪除的貼文')
  assert.equal(completed?.minutes, 20)
  assert.ok(peer.entries.some(entry => entry.service_id === trade && entry.title === '已刪除的貼文'))
  await call(`services/${trade}/rate`, { stars: 5 }, counterparty, 409)
  assert.deepEqual((await call('moderation/chat', { keys: [], senders: [senderKey] })).removed_senders, [senderKey])
  await expectDelivery(packet, false)
  const [[privateRows]] = await db.execute(`SELECT
    (SELECT COUNT(*) FROM help_posts WHERE id IN (?,?)) AS posts,
    (SELECT COUNT(*) FROM items WHERE id=?) AS items,
    (SELECT COUNT(*) FROM ratings WHERE trade_id=?) AS ratings,
    (SELECT COUNT(*) FROM content_reports WHERE target_id IN (?,?)) AS reports,
    (SELECT COUNT(*) FROM member_chat_messages WHERE sender_key=?) AS messages,
    (SELECT COUNT(*) FROM member_chat_identities WHERE sender_key=? AND sender_id IS NULL AND member_id IS NULL) AS tombstones`,
  [oldPost, newPost, item, trade, item, chat.message_id, senderKey, senderKey])
  assert.deepEqual({ ...privateRows }, { posts: 0, items: 0, ratings: 0, reports: 0, messages: 0, tombstones: 1 })
  assert.ok(!peer.members.some(member => member.id === moved.account.id))
  assert.equal((await call('members/' + moved.account.id, null, counterparty)).name, '已刪除的用戶')

  const unusedUsername = 'unused_' + randomUUID().replaceAll('-', '').slice(0, 15)
  const { token: unused } = await call('auth/register', {
    username: unusedUsername, password, name: '無交易會員', community_id: originalDistrict,
  })
  const { id: unusedId } = (await call('home', null, unused)).account
  await call('account/profile', { name: '無交易會員', community_id: nextDistrict }, unused)
  await call('account/delete', { current_password: password }, unused)
  const [[unusedRows]] = await db.execute('SELECT COUNT(*) AS accounts FROM members WHERE id=?', [unusedId])
  assert.equal(unusedRows.accounts, 0)
})
