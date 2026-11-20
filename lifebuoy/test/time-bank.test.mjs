import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import assert from 'node:assert/strict'
import { setTimeout as delay } from 'node:timers/promises'
import { test } from 'node:test'
import mysql from 'mysql2/promise'

test('Nitro and InnoDB time bank', { timeout: 60_000 }, async t => {
  const url = new URL(process.env.NUXT_DATABASE_URL ?? 'invalid:')
  assert.equal(url.hostname, '127.0.0.1')
  assert.equal(url.pathname, '/lifebuoy_test', 'Use the dedicated disposable test database')
  const db = await mysql.createConnection(url.href)
  t.after(() => db.end())
  const [[{ version }]] = await db.query('SELECT VERSION() AS version')
  t.diagnostic(`Database server: ${version}`)
  const port = Number(process.env.LIFEBUOY_TEST_PORT ?? 3391)
  const base = `http://127.0.0.1:${port}/api/v1/`
  const app = spawn(process.execPath, ['.output/server/index.mjs'], {
    env: { ...process.env, NITRO_HOST: '127.0.0.1', NITRO_PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const exited = once(app, 'exit')
  t.after(async () => {
    app.kill()
    await exited
  })
  let logs = ''
  for (const stream of [app.stdout, app.stderr]) {
    stream.on('data', chunk => { logs = (logs + chunk).slice(-4000) })
  }
  let ready = false
  for (let i = 0; i < 80; i++) {
    if (app.exitCode !== null) break
    const probe = await fetch(base + 'home').catch(() => null)
    if (probe?.status === 401) {
      ready = true
      break
    }
    await delay(100)
  }
  assert.ok(ready, logs)
  const community = randomUUID()
  const other = randomUUID()
  const tokens = new Map()
  for (const id of [community, other]) {
    await db.execute('INSERT INTO communities VALUES (?,?)', [id, '驗收社區'])
  }
  for (const [id, tenant, role, balance] of [
    ['payer', community, 'member', 60], ['provider', community, 'member', 0],
    ['new', community, 'member', 0], ['admin', community, 'admin', 0],
    ['helper', community, 'member', 0],
    ['repayment-payer', community, 'member', 60],
    ['repayment-provider', community, 'member', 60],
    ['outsider', other, 'member', 60],
  ]) {
    const token = randomBytes(32).toString('base64url')
    tokens.set(id, token)
    await db.execute('INSERT INTO members VALUES (?,?,?,?,?,?)',
      [tenant, id, id, role, balance, createHash('sha256').update(token).digest()])
  }
  async function request(actor, path, body, status = 200) {
    const response = await fetch(base + path, {
      method: body == null ? 'GET' : 'POST',
      headers: { Authorization: 'Bearer ' + tokens.get(actor), 'Content-Type': 'application/json' },
      body: body == null ? undefined : JSON.stringify(body),
    })
    const value = await response.json()
    assert.equal(response.status, status, JSON.stringify(value) + '\n' + logs)
    return value
  }
  const agreement = { minutes: 30 }
  async function pending() {
    const id = randomUUID()
    const body = { id, kind: 'request', title: '修理腳踏車', area: '驗收區', minutes: 30 }
    await request('payer', 'posts', body)
    await request('payer', 'posts', body)
    await request('provider', `posts/${id}/match`, {})
    await request('provider', `posts/${id}/match`, {})
    await request('payer', `services/${id}/confirm`, agreement, 409)
    await request('payer', `services/${id}/agree`, { minutes: 31 }, 409)
    await request('payer', `services/${id}/agree`, agreement)
    await request('provider', `services/${id}/agree`, agreement)
    return id
  }
  async function balances() {
    const [result] = await db.execute(
      "SELECT balance FROM members WHERE community_id=? AND id IN ('payer','provider') ORDER BY id", [community])
    return result.map(row => row.balance)
  }
  async function entries(id) {
    const [result] = await db.execute(
      'SELECT delta FROM time_entries WHERE community_id=? AND service_id=? ORDER BY delta', [community, id])
    return result.map(row => row.delta)
  }

  await t.test('single confirmation, lost response retry and tenant isolation', async () => {
    const id = await pending()
    const path = `services/${id}/confirm`
    await request('new', path, agreement, 403)
    await request('outsider', path, agreement, 404)
    assert.equal((await request('payer', path, agreement)).state, 'pending')
    assert.deepEqual(await balances(), [60, 0])
    assert.deepEqual(await entries(id), [])
    // Consume the first response without applying it to any client state.
    await request('provider', path, agreement)
    assert.equal((await request('provider', path, agreement)).state, 'settled')
    assert.deepEqual(await balances(), [30, 30])
    assert.deepEqual(await entries(id), [-30, 30])
    const home = await request('provider', 'home')
    assert.equal(home.account.balance, 30)
    assert.equal(home.entries.find(entry => entry.service_id === id).delta, 30)
  })

  await t.test('concurrent confirmations produce one pair of entries', async () => {
    const id = await pending()
    await Promise.all(['payer', 'provider', 'provider', 'payer'].map(
      member => request(member, `services/${id}/confirm`, agreement)))
    assert.deepEqual(await balances(), [0, 60])
    assert.deepEqual(await entries(id), [-30, 30])
  })

  await t.test('opening credit repayment is capped, itemized and refunded on reversal', async () => {
    const payer = 'repayment-payer'
    const provider = 'repayment-provider'
    await db.execute('INSERT INTO time_opening_credits (community_id,member_id,minutes,applied_at) VALUES (?,?,60,UTC_TIMESTAMP(6))', [community, provider])
    async function settle(amount) {
      const id = randomUUID()
      const path = `services/${id}`
      const agreed = { minutes: amount }
      await request(payer, 'posts', { id, kind: 'request', title: '補時驗收', area: '驗收區', ...agreed })
      await request(provider, `posts/${id}/match`, {})
      await request(payer, path + '/agree', agreed)
      await request(provider, path + '/agree', agreed)
      await request(payer, path + '/confirm', agreed)
      await request(provider, path + '/confirm', agreed)
      return id
    }

    const short = await settle(3)
    const regular = await settle(10)
    const home = await request(provider, 'home')
    assert.equal(home.account.balance, 65)
    assert.equal(home.account.opening_credit_remaining, 52)
    assert.deepEqual(home.entries.filter(entry => entry.service_id === short).map(entry => entry.delta), [3, -3])
    assert.deepEqual(home.entries.filter(entry => entry.service_id === regular).map(entry => [entry.kind, entry.delta]),
      [['settlement', 10], ['opening_credit_repayment', -5]])
    assert.ok(!(await request(payer, 'home')).entries.some(entry => entry.kind === 'opening_credit_repayment'))

    // Represent a member whose earlier services have already repaid most of the grant.
    await db.execute('UPDATE time_opening_credits SET repaid_minutes=58 WHERE community_id=? AND member_id=?', [community, provider])
    const capped = await settle(10)
    const afterCap = await settle(10)
    const full = await request(provider, 'home')
    assert.equal(full.account.opening_credit_remaining, 0)
    assert.deepEqual(full.entries.filter(entry => entry.service_id === capped).map(entry => entry.delta), [10, -2])
    assert.deepEqual(full.entries.filter(entry => entry.service_id === afterCap).map(entry => entry.delta), [10])

    const reversal = { reason: '測試補時退回' }
    await request('admin', `services/${capped}/reverse`, reversal)
    await request('admin', `services/${capped}/reverse`, reversal)
    const reversed = await request(provider, 'home')
    assert.equal(reversed.account.opening_credit_remaining, 2)
    assert.equal(reversed.entries.find(entry => entry.service_id === capped && entry.kind === 'opening_credit_repayment_reversal').delta, 2)
  })

  await t.test('insufficient balance does not partially confirm; free help needs no balance', async () => {
    const id = await pending()
    await request('payer', `services/${id}/confirm`, agreement)
    await request('provider', `services/${id}/confirm`, agreement, 409)
    assert.deepEqual(await entries(id), [])
    const [[service]] = await db.execute('SELECT state,provider_confirmed FROM services WHERE community_id=? AND id=?', [community,id])
    assert.deepEqual(service, { state: 'pending', provider_confirmed: 0 })
    await request('new', 'posts', { id: randomUUID(), title: '免費求助', area: '驗收區', kind: 'free' })
  })

  await t.test('failure on credit entry rolls back debit, confirmation and journal', async () => {
    const [[{ id: prior }]] = await db.execute(
      "SELECT id FROM services WHERE community_id=? AND payer_id='payer' AND provider_id='provider' AND state='settled' LIMIT 1", [community])
    const reverse = `services/${prior}/reverse`
    await request('admin', reverse, { reason: '驗收更正' })
    await request('admin', reverse, { reason: '驗收更正' })
    assert.deepEqual(await balances(), [30, 30])
    const id = await pending()
    const path = `services/${id}/confirm`
    await request('payer', path, agreement)
    const trigger = 'test_credit_' + id.replaceAll('-', '')
    try {
      await db.query(`CREATE TRIGGER ${trigger} BEFORE INSERT ON time_entries FOR EACH ROW
        BEGIN IF NEW.service_id = '${id}' AND NEW.delta > 0 THEN
          SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forced credit failure'; END IF; END`)
      await request('provider', path, agreement, 500)
      assert.deepEqual(await balances(), [30, 30])
      assert.deepEqual(await entries(id), [])
      const [[journal]] = await db.execute(
        'SELECT COUNT(*) AS count FROM time_journals WHERE community_id=? AND service_id=?', [community, id])
      assert.equal(journal.count, 0)
      const [[service]] = await db.execute(
        'SELECT state,provider_confirmed FROM services WHERE community_id=? AND id=?', [community, id])
      assert.deepEqual(service, { state: 'pending', provider_confirmed: 0 })
    } finally {
      await db.query(`DROP TRIGGER IF EXISTS ${trigger}`)
    }
    await request('provider', path, agreement)
    assert.deepEqual(await balances(), [0, 60])
    assert.deepEqual(await entries(id), [-30, 30])
  })

  let completedExchange
  await t.test('competing reservations, cancellation, and participant-only handoff', async () => {
    async function item(actor, title) {
      const id = randomUUID()
      await request(actor, 'items', { id, title, wanted: '電池', area: '驗收區' })
      return id
    }
    const [wanted, left, right] = await Promise.all([
      item('payer', '手電筒'), item('provider', '電池'), item('new', '水壺'),
    ])
    const first = randomUUID()
    const second = randomUUID()
    await request('provider', 'exchanges', { id: first, offered: left, wanted, meeting: '公共交收點' })
    await request('new', 'exchanges', { id: second, offered: right, wanted, meeting: '公共交收點' })
    const attempts = await Promise.all([first, second].map(async id => {
      const res = await fetch(base + `exchanges/${id}/accept`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + tokens.get('payer'), 'Content-Type': 'application/json' },
        body: '{}',
      })
      return { id, status: res.status }
    }))
    assert.deepEqual(attempts.map(a => a.status).sort(), [200,409], logs)
    const loser = attempts.find(a => a.status === 409).id
    await request('payer', `exchanges/${attempts.find(a => a.status === 200).id}/cancel`, {})
    const partner = loser === first ? 'provider' : 'new'
    await request('payer', `exchanges/${loser}/accept`, {})
    await request('helper', `exchanges/${loser}/handoff`, {}, 403)
    assert.equal((await request('payer', `exchanges/${loser}/handoff`, {})).state, 'reserved')
    assert.equal((await request(partner, `exchanges/${loser}/handoff`, {})).state, 'completed')
    completedExchange = { id: loser, partner }
  })

  await t.test('ratings appear immediately, count each reviewer once, and respect disputes', async () => {
    const submissions = []
    for (const [reviewer, stars] of [['provider',5], ['new',4], ['helper',3]]) {
      const id = randomUUID()
      await request('payer', 'posts', { id, kind: 'offer', title: '驗收服務', area: '驗收區', minutes: 30 })
      await request(reviewer, `posts/${id}/match`, {})
      // Restore fixture minutes directly in the isolated test database.
      await db.execute('UPDATE members SET balance=30 WHERE community_id=? AND id=?', [community,reviewer])
      for (const action of ['agree','confirm']) {
        await request('payer', `services/${id}/${action}`, agreement)
        await request(reviewer, `services/${id}/${action}`, agreement)
      }
      const rate = `services/${id}/rate`
      await request('outsider', rate, { stars }, 404)
      if (reviewer !== 'helper') await request('helper', rate, { stars }, 403)
      await Promise.all([request(reviewer, rate, { stars }), request(reviewer, rate, { stars })])
      await request(reviewer, rate, { stars: 1 }, 409)
      const home = await request('payer', 'home')
      assert.equal(home.ratings.some(r => r.trade_id === id), false)
      const member = home.members.find(row => row.id === 'payer')
      assert.equal(member.count, submissions.length + 1)
      assert.equal(member.score, (5 + stars) / 2)
      assert.deepEqual(await request('payer', 'members/payer'), member)
      if (reviewer === 'helper') {
        await db.execute('UPDATE services SET completed_at=UTC_TIMESTAMP(6)-INTERVAL 7 DAY WHERE community_id=? AND id=?', [community,id])
        await request('payer', rate, { stars: 5 }, 409)
      } else {
        await request('payer', rate, { stars: 5 })
      }
      submissions.push(id)
    }
    const ratedMember = { id: 'payer', name: 'payer', count: 3, score: 4, completed_count: 6 }
    assert.deepEqual(await request('payer', 'members/payer'), ratedMember)
    assert.deepEqual((await request('payer', 'home')).members.find(row => row.id === 'payer'), ratedMember)
    assert.deepEqual((await request('outsider', 'home')).members,
      [{ id: 'outsider', name: 'outsider', count: 0, score: null, completed_count: 0 }])
    await request('outsider', 'members/payer', null, 404)
    await request('payer', `services/${submissions[0]}/dispute`, { reason: '驗收申訴' })
    assert.equal((await request('payer', 'members/payer')).score, 3.5)
    await request('payer', 'admin', null, 403)
    const dashboard = await request('admin', 'admin')
    assert.equal(dashboard.community, '驗收社區')
    assert.ok(dashboard.members.every(member => member.name !== 'outsider' && !('token_hash' in member)))
    assert.equal(dashboard.disputes.length, 1)
    assert.equal(dashboard.disputes[0].trade_title, '驗收服務')
    assert.equal(dashboard.disputes[0].reporter_name, 'payer')
    const service = dashboard.services.find(row => row.id === submissions[0])
    assert.equal(service.title, '驗收服務')
    assert.equal(service.provider_name, 'payer')
    assert.equal(service.payer_name, 'provider')
    assert.ok(dashboard.ledger.some(row => row.title === '驗收服務' && row.actor_name))
    assert.ok(dashboard.items.some(row => row.title === '手電筒' && row.owner_name === 'payer'))
    assert.ok(dashboard.exchanges.some(row => row.wanted_title === '手電筒' && row.meeting === '公共交收點'))
    assert.ok(dashboard.audit.some(row => row.action === 'service_dispute_open' && row.target_title === '驗收服務'))
    await request('admin', `services/${submissions[0]}/resolve`, { outcome: 'restore', reason: '驗收恢復' })
    assert.equal((await request('payer', 'members/payer')).score, 4)
    // Make the completed exchange the most recent trade with this reviewer.
    await db.execute('UPDATE exchanges SET completed_at=UTC_TIMESTAMP(6) WHERE community_id=? AND id=?',
      [community, completedExchange.id])
    const rateExchange = `exchanges/${completedExchange.id}/rate`
    await request(completedExchange.partner, rateExchange, { stars: 1 })
    const expectedScore = completedExchange.partner === 'provider' ? 2.7 : 3
    assert.deepEqual((await request('payer', 'home')).members.find(row => row.id === 'payer'),
      { ...ratedMember, score: expectedScore })
    await request('payer', rateExchange, { stars: 5 })
  })

  await t.test('self registration, password login, guest board and session revocation', async () => {
    const username = 'qa_' + randomBytes(8).toString('hex')
    const password = randomBytes(18).toString('base64url')
    const district = 'hk-sham-shui-po'
    const credentials = { username, password, community_id: district }
    const postId = randomUUID()
    const [[{ districtCount }]] = await db.query("SELECT COUNT(*) AS districtCount FROM communities WHERE id LIKE 'hk-%'")
    assert.equal(districtCount, 18)
    const missingDistrict = await request('guest', 'auth/register', { username, password, name: '驗收' }, 400)
    assert.match(JSON.stringify(missingDistrict), /district_required/)
    for (const invalid of ['demo', other]) {
      const rejected = await request('guest', 'auth/register', { ...credentials, name: '驗收', community_id: invalid }, 400)
      assert.match(JSON.stringify(rejected), /invalid_district/)
    }
    await request('guest', 'auth/register', { ...credentials, password: 'short', name: '驗收' }, 400)
    const signup = await request('guest', 'auth/register', {
      ...credentials, name: '註冊驗收', role: 'admin', balance: 100000,
    })
    tokens.set('signup', signup.token)
    const home = await request('signup', 'home')
    assert.equal(home.account.role, 'member')
    assert.equal(home.account.balance, 60)
    assert.deepEqual(home.entries.map(({ kind, delta }) => [kind, delta]), [['opening_credit', 60]])
    assert.equal(home.account.community_id, district)
    assert.equal(home.account.name, '註冊驗收')
    await request('signup', 'admin', null, 403)
    await request('guest', 'auth/register', { ...credentials, username: username.toUpperCase(), name: '重複帳號' }, 409)
    await request('guest', 'auth/login', { ...credentials, password: 'wrong-password' }, 401)
    const login = await request('guest', 'auth/login', { username: username.toUpperCase(), password })
    assert.notEqual(login.token, signup.token)
    tokens.set('login', login.token)
    const relogged = await request('login', 'home')
    assert.equal(relogged.account.id, home.account.id)
    assert.equal(relogged.account.balance, 60)
    assert.equal(relogged.entries.length, 1)
    const provider = await request('guest', 'auth/register', {
      username: username + '_helper', password, name: '協助驗收', community_id: district,
    })
    tokens.set('signup-helper', provider.token)
    const elsewhere = await request('guest', 'auth/register', {
      username: username + '_east', password, name: '跨區驗收', community_id: 'hk-eastern',
    })
    tokens.set('signup-elsewhere', elsewhere.token)
    const paid = randomUUID()
    await request('login', 'posts', { id: paid, kind: 'request', title: '測試找支援', area: '驗收區', minutes: 30 })
    const elsewhereHome = await request('signup-elsewhere', 'home')
    assert.equal(elsewhereHome.account.community_id, 'hk-eastern')
    assert.ok(!elsewhereHome.posts.some(post => post.id === paid))
    await request('signup-elsewhere', `posts/${paid}/match`, {}, 404)
    await request('signup-helper', `posts/${paid}/match`, {})
    for (const action of ['agree', 'confirm']) {
      for (const actor of ['login', 'signup-helper']) {
        await request(actor, `services/${paid}/${action}`, { minutes: 30 })
      }
    }
    const payerHome = await request('login', 'home')
    const helperHome = await request('signup-helper', 'home')
    assert.equal(payerHome.account.balance, 30)
    assert.equal(helperHome.account.balance, 85)
    assert.equal(helperHome.account.opening_credit_remaining, 55)
    assert.equal(payerHome.entries.find(entry => entry.service_id === paid).delta, -30)
    assert.equal(helperHome.entries.find(entry => entry.service_id === paid).delta, 30)
    assert.equal(helperHome.entries.find(entry => entry.service_id === paid && entry.kind === 'opening_credit_repayment').delta, -5)
    await request('login', 'posts', { id: postId, kind: 'free', title: '訪客看板驗收', area: '驗收區' })
    const board = await request('guest', 'board')
    assert.deepEqual(Object.keys(board).sort(), ['fetchedAt', 'items', 'posts'])
    assert.equal(board.posts.find(post => post.id === postId)?.community_id, district)
    await request('guest', 'home', null, 401)
    await request('guest', 'items', {}, 401)
    await request('login', 'auth/logout', {})
    await request('login', 'home', null, 401)
    await db.execute('UPDATE member_sessions SET expires_at=UTC_TIMESTAMP(6) WHERE token_hash=?',
      [createHash('sha256').update(signup.token).digest()])
    await request('signup', 'home', null, 401)
  })
})
