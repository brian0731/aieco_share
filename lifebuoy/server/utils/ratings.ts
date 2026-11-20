import type { PoolConnection } from 'mysql2/promise'
import { type Actor, type Db, audit, boundedText, fail, rows } from './database'

export type TradeKind = 'service' | 'exchange'
type Dispute = { reporter_id: string; reason: string; outcome: 'restore' | 'exclude' | null; resolution_reason: string | null }
type Trade = { first: string; second: string; state: string; within_window: number | null }
type Input = Record<string, unknown>

async function lockTrade(db: PoolConnection, actor: Actor, kind: TradeKind, id: string) {
  const [table, first, second] = kind === 'service'
    ? ['services', 'payer_id', 'provider_id']
    : ['exchanges', 'proposer_id', 'owner_id']
  const [trade] = await rows<Trade>(db, `SELECT ${first} AS first,${second} AS second,state,
    UTC_TIMESTAMP(6)<completed_at+INTERVAL 7 DAY AS within_window FROM ${table}
    WHERE community_id=? AND id=? FOR UPDATE`, [actor.community_id,id])
  if (!trade) fail(404, 'trade_not_found')
  return trade
}

async function disputeFor(db: PoolConnection, actor: Actor, kind: TradeKind, id: string) {
  const [dispute] = await rows<Dispute>(db,
    'SELECT * FROM disputes WHERE community_id=? AND kind=? AND trade_id=?', [actor.community_id,kind,id])
  return dispute
}

export async function blockDispute(db: PoolConnection, actor: Actor, kind: TradeKind, id: string) {
  const dispute = await disputeFor(db, actor, kind, id)
  if (dispute && !dispute.outcome) fail(409, 'trade_disputed')
}

export async function changeRating(db: PoolConnection, actor: Actor, kind: TradeKind, id: string, action: string, input: Input) {
  const trade = await lockTrade(db, actor, kind, id)
  const community = actor.community_id
  if (action === 'resolve') {
    if (actor.role !== 'admin') fail(403, 'admin_required')
    const reason = boundedText(input.reason, 500, 'reason_required')
    const outcome = input.outcome
    if (outcome !== 'restore' && outcome !== 'exclude') fail(400, 'invalid_outcome')
    const dispute = await disputeFor(db, actor, kind, id)
    if (!dispute) fail(404, 'dispute_not_found')
    if (dispute.outcome === outcome && dispute.resolution_reason === reason) return { outcome }
    await db.execute('UPDATE disputes SET outcome=?,resolution_reason=? WHERE community_id=? AND kind=? AND trade_id=?',
      [outcome,reason,community,kind,id])
    await audit(db, actor, kind + '_dispute_' + outcome, id, reason)
    return { outcome }
  }
  if (actor.id !== trade.first && actor.id !== trade.second) fail(403, 'participant_required')
  if (action === 'dispute') {
    if (trade.state === 'cancelled' || trade.state === 'reversed') fail(409, 'cannot_dispute')
    const reason = boundedText(input.reason, 500, 'reason_required')
    const previous = await disputeFor(db, actor, kind, id)
    if (previous?.reporter_id === actor.id && previous.reason === reason) return { outcome: previous.outcome }
    if (previous) fail(409, 'dispute_exists')
    await db.execute('INSERT INTO disputes (community_id,kind,trade_id,reporter_id,reason) VALUES (?,?,?,?,?)',
      [community,kind,id,actor.id,reason])
    await audit(db, actor, kind + '_dispute_open', id, reason)
    return { outcome: null }
  }
  const stars = input.stars
  if (typeof stars !== 'number' || !Number.isInteger(stars) || stars < 1 || stars > 5) fail(400, 'invalid_stars')
  const [prior] = await rows<{ stars: number }>(db,
    'SELECT stars FROM ratings WHERE community_id=? AND kind=? AND trade_id=? AND reviewer_id=?',
    [community,kind,id,actor.id])
  if (prior) {
    if (prior.stars !== stars) fail(409, 'rating_exists')
    return prior
  }
  await blockDispute(db, actor, kind, id)
  if (trade.state !== (kind === 'service' ? 'settled' : 'completed') || !trade.within_window) {
    fail(409, 'rating_unavailable')
  }
  const subject = actor.id === trade.first ? trade.second : trade.first
  await db.execute('INSERT INTO ratings (community_id,kind,trade_id,reviewer_id,subject_id,stars) VALUES (?,?,?,?,?,?)',
    [community,kind,id,actor.id,subject,stars])
  return { stars }
}

export async function reputation(db: Db, actor: Actor, id: string) {
  const community = actor.community_id
  const [member] = await rows<{ id: string; name: string }>(db,
    'SELECT id,name FROM members WHERE community_id=? AND id=?', [community,id])
  if (!member) fail(404, 'member_not_found')
  const [stats] = await rows<{ count: number; score: string | null }>(db, `
    WITH trades AS (
      SELECT id,'service' AS kind,completed_at FROM services WHERE community_id=? AND state='settled'
      UNION ALL
      SELECT id,'exchange' AS kind,completed_at FROM exchanges WHERE community_id=? AND state='completed'
    ), ranked AS (
      SELECT r.stars,ROW_NUMBER() OVER (
        PARTITION BY r.reviewer_id ORDER BY t.completed_at DESC,r.kind DESC,r.trade_id DESC
      ) AS position
      FROM ratings r JOIN trades t ON (t.kind,t.id)=(r.kind,r.trade_id)
      LEFT JOIN disputes d ON (d.community_id,d.kind,d.trade_id)=(r.community_id,r.kind,r.trade_id)
      WHERE r.community_id=? AND r.subject_id=? AND (d.trade_id IS NULL OR d.outcome='restore')
        AND (UTC_TIMESTAMP(6)>=t.completed_at+INTERVAL 7 DAY OR EXISTS (
          SELECT 1 FROM ratings peer WHERE (peer.community_id,peer.kind,peer.trade_id,peer.reviewer_id)
          =(r.community_id,r.kind,r.trade_id,r.subject_id)
        ))
    )
    SELECT COUNT(*) AS count,CASE WHEN COUNT(*)>=3 THEN ROUND(AVG(stars),1) END AS score
    FROM ranked WHERE position=1`, [community,community,community,id])
  return { ...member, count: stats.count, score: stats.score == null ? null : Number(stats.score) }
}
