import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import assert from 'node:assert/strict'
import { createServer } from 'node:net'
import { setTimeout as delay } from 'node:timers/promises'
import { test } from 'node:test'
import mysql from 'mysql2/promise'

test('content reports, filtering and moderator removals', { timeout: 30_000 }, async t => {
  const url = new URL(process.env.NUXT_DATABASE_URL ?? 'invalid:')
  assert.equal(url.hostname, '127.0.0.1')
  assert.equal(url.pathname, '/lifebuoy_test')
  const db = await mysql.createConnection(url.href)
  t.after(() => db.end())

  const listener = createServer()
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve))
  const { port } = listener.address()
  await new Promise(resolve => listener.close(resolve))
  const app = spawn(process.execPath, ['.output/server/index.mjs'], {
    env: { ...process.env, NITRO_HOST: '127.0.0.1', NITRO_PORT: String(port) },
    stdio: ['ignore', 'ignore', 'pipe'],
  })
  const exited = once(app, 'exit')
  t.after(async () => { app.kill(); await exited })
  let logs = ''
  app.stderr.on('data', chunk => { logs = (logs + chunk).slice(-4000) })
  const base = 'http://127.0.0.1:' + port + '/api/v1/'
  let ready = false
  for (let attempt = 0; attempt < 80; attempt++) {
    const probe = await fetch(base + 'home').catch(() => null)
    if (probe?.status === 401) { ready = true; break }
    await delay(100)
  }
  assert.ok(ready, logs)
  const community = 'hk-north'
  const tokens = {}
  for (const [key, role] of [['author','member'], ['reporter','member'], ['admin','admin']]) {
    const token = randomBytes(32).toString('base64url')
    tokens[key] = token
    await db.execute('INSERT INTO members (community_id,id,name,role,token_hash) VALUES (?,?,?,?,?)',
      [community, randomUUID(), key, role, createHash('sha256').update(token).digest()])
  }

  async function request(user, path, body, status = 200) {
    const response = await fetch(base + path, {
      method: body == null ? 'GET' : 'POST',
      headers: { 'Content-Type':'application/json', ...(user ? { Authorization:'Bearer ' + tokens[user] } : {}) },
      body: body == null ? undefined : JSON.stringify(body),
    })
    const value = await response.json()
    assert.equal(response.status, status, JSON.stringify(value) + '\n' + logs)
    return value
  }

  const postId = randomUUID()
  const itemId = randomUUID()
  const postTitle = '幫街坊修單車 ' + postId
  const itemTitle = '故事書 ' + itemId
  await request('author', 'posts', { id:postId, kind:'free', title:'打死你', area:'北區' }, 422)
  await request('author', 'items', { id:itemId, title:'故事書', wanted:'販賣毒品', area:'北區' }, 422)
  await request('author', 'posts', { id:postId, kind:'free', title:postTitle, area:'北區' })
  await request('author', 'items', { id:itemId, title:itemTitle, wanted:'拼圖', area:'北區' })
  const post = {kind:'post', target_id:postId, community_id:community, reason:'不當內容'}
  await request(null, 'reports', post, 401)
  await request('author', 'reports', post, 400)
  await request('reporter', 'reports', {...post, content:'客戶端不能覆寫實際內容'})
  await request('reporter', 'reports', post)
  await request('reporter', 'reports', {kind:'item', target_id:itemId, community_id:community, reason:'驗收'})

  const text = '測試光網訊息 ' + randomUUID()
  const packet = {kind:'aieco.light.chat.v1', app:'test', messageId:randomUUID(), senderId:'test-sender', senderName:'光網街坊', text}
  async function openSocket() {
    const socket = new WebSocket('ws://127.0.0.1:' + port + '/ws/light')
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, {once:true})
      socket.addEventListener('error', reject, {once:true})
    })
    t.after(() => socket.close())
    return socket
  }
  const receiver = await openSocket()
  const sender = await openSocket()
  const received = []
  receiver.addEventListener('message', event => received.push(JSON.parse(event.data)))
  // Send a marker after the blocked packet and wait for normal traffic to arrive.
  async function sendAndWait(message, markerText) {
    sender.send(JSON.stringify(message))
    const marker = {...packet, messageId:randomUUID(), text:markerText}
    sender.send(JSON.stringify(marker))
    for (let attempt = 0; attempt < 40; attempt++) {
      if (received.some(entry => entry.messageId === marker.messageId)) break
      await delay(25)
    }
    assert.ok(received.some(entry => entry.messageId === marker.messageId), logs)
    await delay(120)
  }
  const filtered = {...packet, messageId:randomUUID(), text:'打死你'}
  await sendAndWait(filtered, '光網連線確認')
  assert.ok(!received.some(entry => entry.messageId === filtered.messageId))
  await sendAndWait(packet, '第二則正常訊息')
  assert.ok(received.some(entry => entry.messageId === packet.messageId))

  await request('reporter', 'reports', {kind:'chat', target_id:packet.messageId,
    sender_id:packet.senderId, sender_name:packet.senderName, content:packet.text, reason:'聊天室驗收'})
  const { reports } = await request('admin', 'admin')
  const reportedPost = reports.find(row => row.kind === 'post' && row.content.startsWith(postTitle))
  const reportedItem = reports.find(row => row.kind === 'item' && row.content.startsWith(itemTitle))
  const reportedChat = reports.find(row => row.kind === 'chat' && row.content === text)
  assert.ok(reportedPost && reportedItem && reportedChat, JSON.stringify(reports))
  assert.equal(reports.filter(row => row.kind === 'post' && row.content === reportedPost.content).length, 1)
  const remove = {outcome:'removed',reason:'驗收下架'}
  await request('reporter', 'reports/' + reportedPost.id + '/resolve', remove, 403)
  await request('admin', 'reports/' + reportedPost.id + '/resolve', remove)
  await request('admin', 'reports/' + reportedPost.id + '/resolve', remove)
  await request('admin', 'reports/' + reportedItem.id + '/resolve', {outcome:'dismissed',reason:'確認刊登合規'})
  await request('admin', 'reports/' + reportedChat.id + '/resolve', remove)

  const board = await request(null, 'board')
  assert.ok(!board.posts.some(row => row.id === postId))
  assert.ok(board.items.some(row => row.id === itemId))
  const key = createHash('sha256').update(JSON.stringify([packet.messageId, packet.senderId, text])).digest('hex')
  assert.deepEqual(await request(null, 'moderation/chat', {keys:[key]}), {removed:[key], removed_senders:[]})
  received.length = 0
  await sendAndWait(packet, '下架後正常訊息')
  assert.ok(!received.some(entry => entry.messageId === packet.messageId))
})
