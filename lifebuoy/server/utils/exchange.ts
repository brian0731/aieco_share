import type { PoolConnection } from 'mysql2/promise'
import { type Actor, audit, boundedText, fail, rows, uuid } from './database'
import { blockDispute } from './ratings'
import { requireAllowedContent } from './moderation'

type Item = { id: string; owner_id: string; reserved_by: string | null; exchanged: number; withdrawn: number }
export type Exchange = {
  id: string
  offered_id: string
  wanted_id: string
  proposer_id: string
  owner_id: string
  meeting: string
  state: 'proposed' | 'reserved' | 'completed' | 'cancelled'
  expired: number
  proposer_confirmed: number
  owner_confirmed: number
  completed_at: Date | null
}
type Input = Record<string, unknown>

export async function publishItem(db: PoolConnection, actor: Actor, input: Input) {
  const id = uuid(input.id)
  const title = boundedText(input.title, 120, 'invalid_title')
  const wanted = boundedText(input.wanted, 120, 'invalid_wanted')
  const area = boundedText(input.area, 80, 'invalid_area')
  requireAllowedContent(title, wanted, area)
  await db.execute(
    'INSERT INTO items (community_id,id,owner_id,title,wanted,area) VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE id=id',
    [actor.community_id,id,actor.id,title,wanted,area],
  )
  const [item] = await rows<Item & { title: string; wanted: string; area: string }>(db,
    'SELECT * FROM items WHERE community_id=? AND id=? FOR UPDATE', [actor.community_id,id])
  if (item.owner_id !== actor.id || item.title !== title || item.wanted !== wanted || item.area !== area) {
    fail(409, 'item_id_conflict')
  }
  return { id }
}

async function lockItems(db: PoolConnection, community: string, first: string, second: string) {
  const result = new Map<string, Item>()
  for (const id of [first, second].sort()) {
    const [item] = await rows<Item>(db, 'SELECT * FROM items WHERE community_id=? AND id=? FOR UPDATE', [community,id])
    if (!item) fail(404, 'item_not_found')
    result.set(id, item)
  }
  return result
}

export async function lockExchange(db: PoolConnection, actor: Actor, id: string) {
  const [exchange] = await rows<Exchange>(db,
    'SELECT *,expires_at<=UTC_TIMESTAMP(6) AS expired FROM exchanges WHERE community_id=? AND id=? FOR UPDATE',
    [actor.community_id,id])
  if (!exchange) fail(404, 'exchange_not_found')
  return exchange
}

export async function proposeExchange(db: PoolConnection, actor: Actor, input: Input) {
  const id = uuid(input.id)
  const offered = uuid(input.offered)
  const wanted = uuid(input.wanted)
  if (offered === wanted) fail(400, 'different_items_required')
  const meeting = boundedText(input.meeting ?? '待確認的公共交收點', 200, 'invalid_meeting')
  requireAllowedContent(meeting)
  const community = actor.community_id
  // Insert and retries must acquire the exchange lock before locking the items.
  const [prior] = await rows<Exchange>(db, 'SELECT * FROM exchanges WHERE community_id=? AND id=?', [community,id])
  if (prior) {
    if (prior.proposer_id !== actor.id || prior.offered_id !== offered ||
        prior.wanted_id !== wanted || prior.meeting !== meeting) fail(409, 'exchange_id_conflict')
    return prior
  }
  const items = await lockItems(db, community, offered, wanted)
  if (items.get(offered)!.owner_id !== actor.id || items.get(wanted)!.owner_id === actor.id) {
    fail(403, 'item_owner_required')
  }
  const owner = items.get(wanted)!.owner_id
  const [retried] = await rows<Exchange>(db, 'SELECT * FROM exchanges WHERE community_id=? AND id=? FOR UPDATE', [community,id])
  if (retried) {
    if (retried.proposer_id !== actor.id || retried.offered_id !== offered ||
        retried.wanted_id !== wanted || retried.meeting !== meeting) fail(409, 'exchange_id_conflict')
    return retried
  }
  for (const item of items.values()) if (item.withdrawn || item.exchanged || item.reserved_by) fail(409, 'item_unavailable')
  await db.execute(`INSERT INTO exchanges (community_id,id,offered_id,wanted_id,proposer_id,owner_id,meeting)
    VALUES (?,?,?,?,?,?,?)`, [community,id,offered,wanted,actor.id,owner,meeting])
  await audit(db, actor, 'propose_exchange', id)
  return lockExchange(db, actor, id)
}

export async function changeExchange(db: PoolConnection, actor: Actor, id: string, action: string) {
  const current = await lockExchange(db, actor, id)
  const proposer = actor.id === current.proposer_id
  const owner = actor.id === current.owner_id
  const community = actor.community_id
  if (!proposer && !owner && !(action === 'expire' && actor.role === 'admin')) fail(403, 'participant_required')
  await blockDispute(db, actor, 'exchange', id)
  if (action === 'accept') {
    if (!owner) fail(403, 'item_owner_required')
    if (current.state === 'reserved' && !current.expired) return current
    if (current.state !== 'proposed') fail(409, 'exchange_unavailable')
    const items = await lockItems(db, community, current.offered_id, current.wanted_id)
    for (const item of items.values()) {
      if (item.exchanged || item.reserved_by) fail(409, 'item_unavailable')
    }
    await db.execute('UPDATE items SET reserved_by=? WHERE community_id=? AND id IN (?,?)',
      [id,community,current.offered_id,current.wanted_id])
    await db.execute("UPDATE exchanges SET state='reserved',expires_at=UTC_TIMESTAMP(6)+INTERVAL 48 HOUR WHERE community_id=? AND id=?", [community,id])
  } else if (action === 'cancel' || action === 'expire') {
    if (current.state === 'cancelled') return current
    if (current.state === 'completed' || (action === 'expire' && !current.expired)) {
      fail(409, 'cannot_release_exchange')
    }
    if (current.state === 'reserved') {
      await lockItems(db, community, current.offered_id, current.wanted_id)
      await db.execute('UPDATE items SET reserved_by=NULL WHERE community_id=? AND reserved_by=? AND id IN (?,?)',
        [community,id,current.offered_id,current.wanted_id])
    }
    await db.execute("UPDATE exchanges SET state='cancelled' WHERE community_id=? AND id=?", [community,id])
  } else if (action === 'handoff') {
    if (current.state === 'completed') return current
    if (current.state !== 'reserved' || current.expired) fail(409, 'exchange_not_reserved')
    const field = proposer ? 'proposer_confirmed' : 'owner_confirmed'
    if (current[field]) return current
    await db.execute(`UPDATE exchanges SET ${field}=1 WHERE community_id=? AND id=?`, [community,id])
    if (proposer ? current.owner_confirmed : current.proposer_confirmed) {
      await lockItems(db, community, current.offered_id, current.wanted_id)
      await db.execute('UPDATE items SET exchanged=1,reserved_by=NULL WHERE community_id=? AND reserved_by=? AND id IN (?,?)',
        [community,id,current.offered_id,current.wanted_id])
      await db.execute("UPDATE exchanges SET state='completed',completed_at=UTC_TIMESTAMP(6) WHERE community_id=? AND id=?", [community,id])
    }
  } else {
    fail(404, 'unknown_action')
  }
  await audit(db, actor, action + '_exchange', id)
  return lockExchange(db, actor, id)
}
