import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { createServer } from 'node:net'
import { randomUUID } from 'node:crypto'
import { setTimeout as delay } from 'node:timers/promises'
import { test } from 'node:test'
import mysql from 'mysql2/promise'
import { importRelay, normalizeRelay, registerRelay } from '../shared/lightmesh-registry.mjs'

test('Lightmesh directory and WebSocket relay', { timeout: 30_000 }, async t => {
  const url = new URL(process.env.NUXT_DATABASE_URL ?? 'invalid:')
  assert.equal(url.hostname, '127.0.0.1')
  assert.equal(url.pathname, '/lifebuoy_test')
  const db = mysql.createPool(url.href)
  const suffix = randomUUID()
  t.after(async () => {
    await db.execute('DELETE FROM lightmesh_networks WHERE relay LIKE ?', ['%/' + suffix])
    await db.end()
  })

  const first = await startRelay(t)
  const second = await startRelay(t)
  const firstUrl = first.replace('http:', 'ws:') + '/ws/light'
  const secondUrl = second.replace('http:', 'ws:') + '/ws/light'
  const relayA = firstUrl + '/' + suffix
  const relayB = secondUrl + '/' + suffix
  assert.equal(normalizeRelay(' WSS://Example.COM:443 '), 'wss://example.com/')
  assert.equal(normalizeRelay('wss://user@example.com/ws'), null)
  assert.equal(normalizeRelay('wss://example.com/ws#'), null)

  const registrations = await Promise.all([
    registerRelay(db, relayA, () => 532),
    registerRelay(db, relayA, () => 532),
  ])
  assert.deepEqual(registrations[0], registrations[1])
  let collisions = 0
  const other = await registerRelay(db, relayB, () => ++collisions === 1 ? 532 : 533)
  assert.equal(collisions, 2)
  assert.equal(registrations[0].code, '000532')
  assert.equal(other.code, '000533')
  const legacyRelay = 'wss://legacy.example.test/' + suffix
  const legacy = await importRelay(db, '000534', legacyRelay)
  assert.deepEqual(await importRelay(db, '000534', legacyRelay), legacy)
  await assert.rejects(importRelay(db, '000534', relayA), /already assigned/)
  await assert.rejects(importRelay(db, '000535', legacyRelay), /already assigned/)
  assert.deepEqual(await registerRelay(db, legacyRelay), legacy)
  await assert.rejects(registerRelay(db, 'wss://example.invalid/' + suffix, () => 532), /unique connection code/)
  const get = path => fetch(first + '/api/lightmesh/' + path)
  assert.equal((await get('health')).status, 200)
  const lookup = await get('networks/000532')
  assert.equal(lookup.headers.get('cache-control'), 'no-store')
  assert.deepEqual(await lookup.json(), registrations[0])
  assert.deepEqual(await (await get('networks/000534')).json(), legacy)
  assert.deepEqual(await (await fetch(second + '/api/lightmesh/networks/000533')).json(), other)
  assert.deepEqual(await (await get('networks?relay=' + encodeURIComponent(relayB))).json(), { code: '000533' })
  assert.equal((await get('networks/123')).status, 400)
  assert.equal((await get('networks?relay=not-a-url')).status, 400)
  assert.equal((await get('networks?relay=' + encodeURIComponent(relayA + '-unknown'))).status, 404)

  const a = await openSocket(t, firstUrl)
  const b = await openSocket(t, secondUrl)
  const bridgeA = await openSocket(t, firstUrl)
  const bridgeB = await openSocket(t, secondUrl)
  bridgeA.addEventListener('message', event => bridgeB.send(event.data))
  bridgeB.addEventListener('message', event => bridgeA.send(event.data))
  const receivedA = []
  const receivedB = []
  a.addEventListener('message', event => receivedA.push(event.data))
  b.addEventListener('message', event => receivedB.push(event.data))
  const payload = JSON.stringify({
    kind: 'aieco.light.chat.v1', app: 'lifebuoy',
    messageId: 'a', roomId: 'public', _lightBridgePath: ['network-a'], extra: '互助',
  })
  const reply = payload.replace('"a"', '"b"')
  a.send('not-json')
  a.send('{"kind":"aieco.light.room.v1","app":null}')
  a.send(payload)
  await until(() => receivedB.length > 0)
  b.send(reply)
  await until(() => receivedA.length > 0)
  assert.deepEqual(receivedB, [payload])
  assert.deepEqual(receivedA, [reply])

  const oversized = await openSocket(t, firstUrl)
  const closed = once(oversized, 'close')
  oversized.send('x'.repeat(65537))
  assert.equal((await closed)[0].code, 1009)
  const next = receivedB.length + 1
  a.send(payload)
  await until(() => receivedB.length === next)
})

async function startRelay(t) {
  const listener = createServer()
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve))
  const { port } = listener.address()
  await new Promise(resolve => listener.close(resolve))
  const child = spawn(process.execPath, ['.output/server/index.mjs'], {
    env: { ...process.env, NITRO_HOST: '127.0.0.1', NITRO_PORT: String(port) },
    stdio: 'ignore',
  })
  t.after(() => child.kill())
  const origin = 'http://127.0.0.1:' + port
  await until(async () => (await fetch(origin + '/api/lightmesh/health').catch(() => null))?.ok)
  return origin
}

async function openSocket(t, url) {
  const socket = new WebSocket(url)
  t.after(() => socket.close())
  await once(socket, 'open')
  return socket
}

async function until(predicate) {
  for (let i = 0; i < 100; i++) {
    if (await predicate()) return
    await delay(30)
  }
  assert.fail('Timed out waiting for Lightmesh')
}
