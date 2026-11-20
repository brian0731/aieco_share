import { authenticate, bearerDigest, boundedText, database, fail, jsonInput, rows, transaction, uuid, type Db } from '../../utils/database'
import { changeService, matchHelp, publishHelp } from '../../utils/time-bank'
import { changeExchange, proposeExchange, publishItem } from '../../utils/exchange'
import { changeRating, reputation } from '../../utils/ratings'
import { loginMember, loginRateLimit, registerMember } from '../../utils/member-auth'
import { hongKongDistrictIds } from '../../utils/districts'

async function publicBoard(db: Db, communities: readonly string[]) {
  const districtParameters = communities.map(() => '?').join(',')
  const [posts, items] = await Promise.all([
    rows(db, `SELECT p.id,p.community_id,p.kind,p.title,p.area,p.minutes,p.author_id,m.name AS author,
      EXISTS(SELECT 1 FROM services s WHERE s.community_id=p.community_id AND s.post_id=p.id) AS matched
      FROM help_posts p JOIN members m ON (m.community_id,m.id)=(p.community_id,p.author_id)
      WHERE p.community_id IN (${districtParameters})
      ORDER BY p.created_at DESC,p.community_id,p.id DESC LIMIT 100`, [...communities]),
    rows(db, `SELECT id,community_id,owner_id,title,wanted,area,(reserved_by IS NOT NULL) AS reserved
      FROM items WHERE community_id IN (${districtParameters}) AND exchanged=0
      ORDER BY created_at DESC,community_id,id DESC LIMIT 100`, [...communities]),
  ])
  return { posts, items, fetchedAt: new Date().toISOString() }
}

export default defineEventHandler(async (event) => {
  const db = database(event)
  const [resource, id, action, ...extra] = (getRouterParam(event, 'path') ?? '').split('/')
  if (extra.length) fail(404, 'unknown_route')
  if (event.method === 'GET' && resource === 'board' && !id) {
    setResponseHeader(event, 'Cache-Control', 'no-store')
    return publicBoard(db, [...hongKongDistrictIds, 'demo'])
  }
  if (event.method === 'POST' && resource === 'auth' && !action) {
    setResponseHeader(event, 'Cache-Control', 'no-store')
    if (id === 'logout') {
      await db.execute('DELETE FROM member_sessions WHERE token_hash=?', [bearerDigest(event)])
      return { ok: true }
    }
    if (id === 'register' || id === 'login') {
      loginRateLimit(event)
      const input = await jsonInput(event)
      if (id === 'register') return registerMember(db, input)
      return loginMember(db, input)
    }
  }
  const actor = await authenticate(event, db)
  const community = actor.community_id
  if (event.method === 'GET' && resource === 'members' && id && !action) {
    return reputation(db, actor, boundedText(id, 36, 'invalid_member'))
  }
  if (event.method === 'GET' && !id && resource === 'admin') {
    if (actor.role !== 'admin') fail(403, 'admin_required')
    const [members, services, ledger, items, exchanges, disputes, audit] = await Promise.all([
      rows(db, 'SELECT id,name,role,balance FROM members WHERE community_id=? ORDER BY id LIMIT 100', [community]),
      rows(db, 'SELECT * FROM services WHERE community_id=? ORDER BY id LIMIT 100', [community]),
      rows(db, 'SELECT * FROM time_journals WHERE community_id=? ORDER BY created_at DESC LIMIT 100', [community]),
      rows(db, 'SELECT * FROM items WHERE community_id=? ORDER BY created_at DESC LIMIT 100', [community]),
      rows(db, `SELECT id,offered_id,wanted_id,proposer_id,owner_id,state,expires_at,completed_at
        FROM exchanges WHERE community_id=? ORDER BY id LIMIT 100`, [community]),
      rows(db, 'SELECT * FROM disputes WHERE community_id=? ORDER BY created_at DESC LIMIT 100', [community]),
      rows(db, 'SELECT * FROM audit_log WHERE community_id=? ORDER BY id DESC LIMIT 100', [community]),
    ])
    return { members, services, ledger, items, exchanges, disputes, audit }
  }
  if (event.method === 'GET' && !id && resource === 'home') {
    const [[account], board, services, entries, members, exchanges, ratings, disputes] = await Promise.all([
      rows(db, 'SELECT community_id,id,name,role,balance FROM members WHERE community_id=? AND id=?', [community, actor.id]),
      publicBoard(db, [community]),
      rows(db, `SELECT s.*,p.title FROM services s JOIN help_posts p
        ON (p.community_id,p.id)=(s.community_id,s.post_id)
        WHERE s.community_id=? AND (s.payer_id=? OR s.provider_id=?)
        ORDER BY p.created_at DESC,s.id DESC LIMIT 100`, [community, actor.id, actor.id]),
      rows<{ delta: number | string }>(db, `SELECT e.service_id,e.kind,e.delta,j.created_at,p.title
        FROM time_entries e JOIN time_journals j USING(community_id,service_id,kind)
        JOIN services s ON (s.community_id,s.id)=(e.community_id,e.service_id)
        JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
        WHERE e.community_id=? AND e.member_id=?
        UNION ALL
        SELECT NULL,'opening_credit',minutes,applied_at,NULL FROM time_opening_credits
        WHERE community_id=? AND member_id=? AND applied_at IS NOT NULL
        ORDER BY created_at DESC,service_id DESC,kind DESC LIMIT 100`, [community, actor.id, community, actor.id]),
      rows(db, 'SELECT id,name FROM members WHERE community_id=? ORDER BY name,id LIMIT 100', [community]),
      rows(db, `SELECT e.*,e.expires_at<=UTC_TIMESTAMP(6) AS expired,
        o.title AS offered_title,w.title AS wanted_title FROM exchanges e
        JOIN items o ON (o.community_id,o.id)=(e.community_id,e.offered_id)
        JOIN items w ON (w.community_id,w.id)=(e.community_id,e.wanted_id)
        WHERE e.community_id=? AND (e.proposer_id=? OR e.owner_id=?)
        ORDER BY e.id LIMIT 100`, [community, actor.id, actor.id]),
      rows(db, 'SELECT kind,trade_id,stars FROM ratings WHERE community_id=? AND reviewer_id=? LIMIT 200', [community, actor.id]),
      rows(db, `SELECT d.kind,d.trade_id,d.reason,d.outcome,d.resolution_reason FROM disputes d
        LEFT JOIN services s ON d.kind='service' AND (s.community_id,s.id)=(d.community_id,d.trade_id)
        LEFT JOIN exchanges e ON d.kind='exchange' AND (e.community_id,e.id)=(d.community_id,d.trade_id)
        WHERE d.community_id=? AND ? IN (s.payer_id,s.provider_id,e.proposer_id,e.owner_id) LIMIT 200`,
        [community, actor.id]),
    ])
    return {
      ...board, account, services,
      entries: entries.map(entry => ({ ...entry, delta: Number(entry.delta) })),
      members, exchanges, ratings, disputes,
    }
  }
  if (event.method !== 'POST') fail(404, 'unknown_route')
  const input = await jsonInput(event)
  if (resource === 'posts' && !id) return transaction(db, conn => publishHelp(conn, actor, input))
  if (resource === 'posts' && action === 'match') return transaction(db, conn => matchHelp(conn, actor, uuid(id)))
  if (resource === 'items' && !id) return transaction(db, conn => publishItem(conn, actor, input))
  if (resource === 'exchanges' && !id) return transaction(db, conn => proposeExchange(conn, actor, input))
  if ((resource === 'services' || resource === 'exchanges') &&
      (action === 'rate' || action === 'dispute' || action === 'resolve')) {
    const kind = resource === 'services' ? 'service' : 'exchange'
    return transaction(db, conn => changeRating(conn, actor, kind, uuid(id), action, input))
  }
  if (resource === 'exchanges' && action) {
    return transaction(db, conn => changeExchange(conn, actor, uuid(id), action))
  }
  if (resource === 'services' && action) {
    return transaction(db, conn => changeService(conn, actor, uuid(id), action, input))
  }
  fail(404, 'unknown_route')
})
