import { type PoolConnection } from 'mysql2/promise'
import { type Actor, audit, boundedText, fail, minutes, rows, uuid } from './database'
import { blockDispute } from './ratings'

export type HelpPost = {
  id: string
  author_id: string
  kind: 'request' | 'offer' | 'free'
  title: string
  area: string
  minutes: number | null
}
export type Service = {
  id: string
  minutes: number
  payer_id: string
  provider_id: string
  payer_agreed: number
  provider_agreed: number
  payer_confirmed: number
  provider_confirmed: number
  state: 'agreement' | 'pending' | 'settled' | 'cancelled' | 'reversed'
  completed_at: Date | null
}
type Input = Record<string, unknown>

export async function publishHelp(db: PoolConnection, actor: Actor, input: Input) {
  const id = uuid(input.id)
  const kind = input.kind
  if (kind !== 'request' && kind !== 'offer' && kind !== 'free') fail(400, 'invalid_kind')
  const title = boundedText(input.title, 120, 'invalid_title')
  const area = boundedText(input.area, 80, 'invalid_area')
  const duration = kind === 'free' ? null : minutes(input.minutes)
  await db.execute(
    `INSERT INTO help_posts (community_id, id, author_id, kind, title, area, minutes)
     VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE id = id`,
    [actor.community_id, id, actor.id, kind, title, area, duration],
  )
  const [post] = await rows<HelpPost>(db, 'SELECT * FROM help_posts WHERE community_id=? AND id=? FOR UPDATE', [actor.community_id, id])
  if (!post || post.author_id !== actor.id || post.kind !== kind || post.title !== title ||
      post.area !== area || post.minutes !== duration) fail(409, 'post_id_conflict')
  return { id }
}

export async function matchHelp(db: PoolConnection, actor: Actor, id: string) {
  const community = actor.community_id
  const [post] = await rows<HelpPost>(db, 'SELECT * FROM help_posts WHERE community_id=? AND id=? FOR UPDATE', [community, id])
  if (!post) fail(404, 'post_not_found')
  if (post.kind === 'free' || post.author_id === actor.id) fail(409, 'post_not_matchable')
  const payer = post.kind === 'request' ? post.author_id : actor.id
  const provider = post.kind === 'offer' ? post.author_id : actor.id
  const [existing] = await rows<Service>(db, 'SELECT * FROM services WHERE community_id=? AND post_id=? FOR UPDATE', [community, id])
  if (existing) {
    if (existing.payer_id !== payer || existing.provider_id !== provider) fail(409, 'already_matched')
    return existing
  }
  await db.execute(
    'INSERT INTO services (community_id,id,post_id,payer_id,provider_id,minutes) VALUES (?,?,?,?,?,?)',
    [community, id, id, payer, provider, post.minutes],
  )
  await audit(db, actor, 'match_service', id)
  return lockService(db, actor, id)
}

export async function lockService(db: PoolConnection, actor: Actor, id: string) {
  const [service] = await rows<Service>(db, 'SELECT * FROM services WHERE community_id=? AND id=? FOR UPDATE', [actor.community_id, id])
  if (!service) fail(404, 'service_not_found')
  return service
}

async function postJournal(db: PoolConnection, actor: Actor, service: Service, kind: 'settlement' | 'reversal', reason?: string) {
  const community = actor.community_id
  const [debit, credit] = kind === 'settlement'
    ? [service.payer_id, service.provider_id]
    : [service.provider_id, service.payer_id]

  for (const id of [debit, credit].sort()) {
    const [account] = await rows<{ balance: number }>(db,
      'SELECT balance FROM members WHERE community_id=? AND id=? FOR UPDATE', [community, id])
    if (!account || (id === debit && account.balance < service.minutes)) fail(409, 'insufficient_balance')
  }
  await db.execute(
    'INSERT INTO time_journals (community_id,service_id,kind,actor_id,reason) VALUES (?,?,?,?,?)',
    [community, service.id, kind, actor.id, reason ?? null],
  )
  for (const [owner, delta] of [[debit, -service.minutes], [credit, service.minutes]]) {
    await db.execute(
      'INSERT INTO time_entries (community_id,service_id,kind,member_id,delta) VALUES (?,?,?,?,?)',
      [community, service.id, kind, owner, delta],
    )
    await db.execute('UPDATE members SET balance=balance+? WHERE community_id=? AND id=?',
      [delta, community, owner])
  }
}

export async function changeService(db: PoolConnection, actor: Actor, id: string, action: string, input: Input) {
  const service = await lockService(db, actor, id)
  const community = actor.community_id
  const payer = service.payer_id === actor.id
  if (action === 'reverse') {
    if (actor.role !== 'admin') fail(403, 'admin_required')
    const reason = boundedText(input.reason, 500, 'reason_required')
    if (service.state === 'reversed') {
      const [prior] = await rows<{ reason: string }>(db,
        "SELECT reason FROM time_journals WHERE community_id=? AND service_id=? AND kind='reversal'", [community, id])
      if (prior?.reason !== reason) fail(409, 'already_reversed')
      return service
    }
    if (service.state !== 'settled') fail(409, 'service_not_settled')
    await postJournal(db, actor, service, 'reversal', reason)
    await db.execute("UPDATE services SET state='reversed' WHERE community_id=? AND id=?", [community, id])
    await audit(db, actor, 'reverse_service', id, reason)
    return lockService(db, actor, id)
  }
  if (!payer && service.provider_id !== actor.id) fail(403, 'participant_required')
  await blockDispute(db, actor, 'service', id)
  if (minutes(input.minutes) !== service.minutes) fail(409, 'minutes_mismatch')
  if (action === 'agree') {
    const field = payer ? 'payer_agreed' : 'provider_agreed'
    if (service[field]) return service
    if (service.state !== 'agreement') fail(409, 'not_awaiting_agreement')
    await db.execute(`UPDATE services SET ${field}=1 WHERE community_id=? AND id=?`, [community, id])
    if (payer ? service.provider_agreed : service.payer_agreed) {
      await db.execute("UPDATE services SET state='pending' WHERE community_id=? AND id=?", [community, id])
    }
  } else if (action === 'confirm') {
    if (service.state === 'settled') return service
    if (service.state !== 'pending') fail(409, 'not_awaiting_confirmation')
    const field = payer ? 'payer_confirmed' : 'provider_confirmed'
    if (service[field]) return service
    await db.execute(`UPDATE services SET ${field}=1 WHERE community_id=? AND id=?`, [community, id])
    if (payer ? service.provider_confirmed : service.payer_confirmed) {
      await postJournal(db, actor, service, 'settlement')
      await db.execute(
        "UPDATE services SET state='settled', completed_at=UTC_TIMESTAMP(6) WHERE community_id=? AND id=?",
        [community, id],
      )
      await audit(db, actor, 'settle_service', id)
    }
  } else {
    fail(404, 'unknown_action')
  }
  await audit(db, actor, action + '_service', id)
  return lockService(db, actor, id)
}
