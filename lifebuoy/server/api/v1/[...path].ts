import { authenticate, bearerDigest, boundedText, database, fail, jsonInput, lockMembership, memberDistricts, rows, transaction, uuid, type Db } from '../../utils/database'
import { changeService, matchHelp, publishHelp } from '../../utils/time-bank'
import { changeExchange, proposeExchange, publishItem } from '../../utils/exchange'
import { changeRating, memberReputations, reputation } from '../../utils/ratings'
import { loginMember, loginRateLimit, registerMember } from '../../utils/member-auth'
import { hongKongDistrictIds } from '../../utils/districts'
import { adminDashboard, adminMemberPage } from '../../utils/admin-dashboard'
import { changeMemberSettings } from '../../utils/member-settings'
import { reportContent, resolveReport } from '../../utils/moderation'
import { checkChatModeration, prepareMemberMessage } from '../../utils/member-chat'

async function publicBoard(db: Db, communities: readonly string[]) {
  const districtParameters = communities.map(() => '?').join(',')
  const [posts, items] = await Promise.all([
    rows(db, `SELECT p.id,p.community_id,p.kind,p.title,p.area,p.minutes,p.author_id,m.name AS author,
      COALESCE(m.origin_community_id,m.community_id) AS author_origin,
      EXISTS(SELECT 1 FROM services s WHERE s.community_id=p.community_id AND s.post_id=p.id) AS matched
      FROM help_posts p JOIN members m ON (m.community_id,m.id)=(p.community_id,p.author_id)
      WHERE p.community_id IN (${districtParameters}) AND p.withdrawn=FALSE
      ORDER BY p.created_at DESC,p.community_id,p.id DESC LIMIT 100`, [...communities]),
    rows(db, `SELECT i.id,i.community_id,i.owner_id,i.title,i.wanted,i.area,(i.reserved_by IS NOT NULL) AS reserved,
      COALESCE(m.origin_community_id,m.community_id) AS owner_origin,m.name AS owner
      FROM items i JOIN members m ON (m.community_id,m.id)=(i.community_id,i.owner_id)
      WHERE i.community_id IN (${districtParameters}) AND i.exchanged=0 AND i.withdrawn=FALSE
      ORDER BY i.created_at DESC,i.community_id,i.id DESC LIMIT 100`, [...communities]),
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
  if (event.method === 'POST' && resource === 'moderation' && id === 'chat' && !action) {
    setResponseHeader(event, 'Cache-Control', 'no-store')
    return checkChatModeration(db, await jsonInput(event))
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
  if (event.method === 'GET' && resource === 'admin' && !action && (!id || id === 'members')) {
    if (actor.role !== 'admin') fail(403, 'admin_required')
    if (id === 'members') return adminMemberPage(db, actor, getQuery(event))
    return adminDashboard(db, actor)
  }
  if (event.method === 'GET' && !id && resource === 'home') {
    const { origin, districts } = await memberDistricts(db, actor)
    const scope = districts.map(() => '?').join(',')
    const [[account], board, services, entries, members, exchanges, ratings, disputes] = await Promise.all([
      rows(db, `SELECT m.community_id,m.id,m.name,m.role,original.balance,
        c.minutes - c.repaid_minutes AS opening_credit_remaining
        FROM members m JOIN members original
          ON original.community_id=COALESCE(m.origin_community_id,m.community_id) AND original.id=m.id
        LEFT JOIN time_opening_credits c
          ON (c.community_id,c.member_id)=(original.community_id,original.id) AND c.applied_at IS NOT NULL
        WHERE m.community_id=? AND m.id=?`, [community, actor.id]),
      publicBoard(db, [community]),
      rows(db, `SELECT s.*,p.title FROM services s JOIN help_posts p
        ON (p.community_id,p.id)=(s.community_id,s.post_id)
        WHERE s.community_id IN (${scope}) AND (s.payer_id=? OR s.provider_id=?)
        ORDER BY p.created_at DESC,s.id DESC LIMIT 100`, [...districts, actor.id, actor.id]),
      rows<{ delta: number | string, entry_order: number }>(db, `SELECT e.service_id,e.kind,e.delta,j.created_at,p.title,0 AS entry_order
        FROM time_entries e JOIN time_journals j USING(community_id,service_id,kind)
        JOIN services s ON (s.community_id,s.id)=(e.community_id,e.service_id)
        JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
        WHERE e.community_id IN (${scope}) AND e.member_id=?
        UNION ALL
        SELECT e.service_id,IF(e.kind='settlement','opening_credit_repayment','opening_credit_repayment_reversal'),
          CAST(j.opening_credit_repayment AS SIGNED) * IF(e.kind='settlement',-1,1),j.created_at,p.title,1
        FROM time_entries e JOIN time_journals j USING(community_id,service_id,kind)
        JOIN services s ON (s.community_id,s.id)=(e.community_id,e.service_id) AND s.provider_id=e.member_id
        JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
        WHERE e.community_id IN (${scope}) AND e.member_id=? AND j.opening_credit_repayment>0
        UNION ALL
        SELECT NULL,'opening_credit',minutes,applied_at,NULL,0 FROM time_opening_credits
        WHERE community_id=? AND member_id=? AND applied_at IS NOT NULL
        ORDER BY created_at DESC,service_id DESC,entry_order,kind DESC LIMIT 100`,
        [...districts, actor.id, ...districts, actor.id, origin, actor.id]),
      memberReputations(db, community),
      rows(db, `SELECT e.*,e.expires_at<=UTC_TIMESTAMP(6) AS expired,
        o.title AS offered_title,w.title AS wanted_title FROM exchanges e
        JOIN items o ON (o.community_id,o.id)=(e.community_id,e.offered_id)
        JOIN items w ON (w.community_id,w.id)=(e.community_id,e.wanted_id)
        WHERE e.community_id IN (${scope}) AND (e.proposer_id=? OR e.owner_id=?)
        ORDER BY e.id LIMIT 100`, [...districts, actor.id, actor.id]),
      rows(db, `SELECT kind,trade_id,stars FROM ratings WHERE community_id IN (${scope}) AND reviewer_id=? LIMIT 200`, [...districts, actor.id]),
      rows(db, `SELECT d.kind,d.trade_id,d.reason,d.outcome,d.resolution_reason FROM disputes d
        LEFT JOIN services s ON d.kind='service' AND (s.community_id,s.id)=(d.community_id,d.trade_id)
        LEFT JOIN exchanges e ON d.kind='exchange' AND (e.community_id,e.id)=(d.community_id,d.trade_id)
        WHERE d.community_id IN (${scope}) AND ? IN (s.payer_id,s.provider_id,e.proposer_id,e.owner_id) LIMIT 200`,
        [...districts, actor.id]),
    ])
    return {
      ...board, account, services,
      entries: entries.map(({ entry_order, ...entry }) => ({
        ...entry, delta: Number(entry.delta),
      })),
      members, exchanges, ratings, disputes,
    }
  }
  if (event.method !== 'POST') fail(404, 'unknown_route')
  const input = await jsonInput(event, resource === 'reports' && !id ? 32768 : undefined)
  if (resource === 'reports' && !id && !action) {
    return transaction(db, async conn => {
      await lockMembership(conn, actor)
      const current = await authenticate(event, conn)
      if (current.id !== actor.id || current.community_id !== actor.community_id) fail(401, 'invalid_token')
      return reportContent(conn, actor, input)
    })
  }
  if (resource === 'reports' && id && action === 'resolve') {
    if (actor.role !== 'admin') fail(403, 'admin_required')
    return transaction(db, conn => resolveReport(conn, actor, id, input))
  }
  const accountAction = resource === 'account' && id && !action
  const postingAction = resource === 'posts' || resource === 'items' || (resource === 'exchanges' && !id)
  if (resource === 'account' && (id === 'password' || id === 'delete') && !action) loginRateLimit(event)
  const chatAction = resource === 'chat' && id === 'messages' && !action
  if (accountAction || postingAction || chatAction) {
    return transaction(db, async conn => {
      const member = await lockMembership(conn, actor)
      const current = await authenticate(event, conn)
      if (current.id !== actor.id || current.community_id !== community) fail(401, 'invalid_token')
      if (accountAction) return changeMemberSettings(conn, member, id, input)
      if (chatAction) return prepareMemberMessage(conn, member, input)
      if (resource === 'posts' && !id) return publishHelp(conn, actor, input)
      if (resource === 'posts' && action === 'match') return matchHelp(conn, actor, uuid(id))
      if (resource === 'items' && !id) return publishItem(conn, actor, input)
      if (resource === 'exchanges' && !id) return proposeExchange(conn, actor, input)
      fail(404, 'unknown_route')
    })
  }
  if ((resource !== 'services' && resource !== 'exchanges') || !action) fail(404, 'unknown_route')
  const tradeId = uuid(id)
  const kind = resource === 'services' ? 'service' : 'exchange'
  let tradeActor = actor
  if (actor.role === 'member') {
    // Resolve the historical district before starting the transaction, so the
    // trade lock is acquired before establishing a transaction-wide read view.
    const { districts } = await memberDistricts(db, actor)
    if (districts.length > 1) {
      const participants = kind === 'service' ? 'payer_id,provider_id' : 'proposer_id,owner_id'
      const [trade] = await rows<{ community_id: string }>(db,
        `SELECT community_id FROM ${resource} WHERE id=? AND ? IN (${participants})
          AND community_id IN (${districts.map(() => '?').join(',')})
          ORDER BY community_id=? DESC LIMIT 1`, [tradeId, actor.id, ...districts, community])
      if (trade) tradeActor = { ...actor, community_id: trade.community_id }
    }
  }
  return transaction(db, async conn => {
    if (action === 'rate' || action === 'dispute' || action === 'resolve') {
      return changeRating(conn, tradeActor, kind, tradeId, action, input)
    }
    return kind === 'exchange'
      ? changeExchange(conn, tradeActor, tradeId, action)
      : changeService(conn, tradeActor, tradeId, action, input)
  })
})
