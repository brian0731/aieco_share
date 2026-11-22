import { createHash, randomUUID } from 'node:crypto'
import type { PoolConnection } from 'mysql2/promise'
import { audit, boundedText, fail, rows, uuid, type Actor, type Db } from './database'
import { hongKongDistrictIds } from './districts'

const blockedContent = /色情|裸照|裸聊|援交|性交易|強姦|種族歧視|殺了你|打死你|炸死你|出售毒品|販賣毒品|\b(?:porn|rape|kill you|drug deal)\b/iu

export function contentAllowed(...fields: string[]) {
  return fields.every(field => !blockedContent.test(field.normalize('NFKC').replace(/\p{Cf}/gu, '').replace(/\s+/g, ' ')))
}

export function requireAllowedContent(...fields: string[]) {
  if (!contentAllowed(...fields)) fail(422, 'content_blocked')
}

type Input = Record<string, unknown>
type Kind = 'post' | 'item' | 'chat'
type Report = {
  id: string
  kind: Kind
  target_key: string
  target_id: string
  target_community_id: string | null
  state: 'pending' | 'dismissed' | 'removed'
}

function fingerprint(...parts: string[]) {
  return createHash('sha256').update(JSON.stringify(parts)).digest('hex')
}

export function chatFingerprint(messageId: string, senderId: string, text: string) {
  return fingerprint(messageId.trim(), senderId.trim(), text.trim())
}

export function chatSenderKey(sender: string) {
  return createHash('sha256').update(sender.trim()).digest('hex')
}

export async function removedChatKeys(db: Db, keys: string[]) {
  if (keys.length === 0) return []
  const matches = await rows<{ message_key: string }>(db, `SELECT message_key FROM removed_chat_messages
    WHERE message_key IN (${keys.map(() => '?').join(',')})`, keys)
  return matches.map(row => row.message_key)
}

export function moderationKeys(keys: unknown): string[] {
  if (!Array.isArray(keys) || keys.length > 100 ||
      keys.some(key => typeof key !== 'string' || !/^[0-9a-f]{64}$/.test(key))) fail(400, 'invalid_chat_keys')
  return keys
}

function listingScope(actor: Actor) {
  return [...new Set([...hongKongDistrictIds, 'demo', actor.community_id])]
}

async function listingEvidence(db: Db, actor: Actor, kind: 'post' | 'item', input: Input) {
  const id = uuid(input.target_id)
  const community = boundedText(input.community_id, 36, 'invalid_district')
  if (!listingScope(actor).includes(community)) fail(404, 'content_not_found')
  const table = kind === 'post' ? 'help_posts' : 'items'
  const owner = kind === 'post' ? 'author_id' : 'owner_id'
  const [listing] = await rows<{ member_id: string, name: string, content: string }>(db, `SELECT
    l.${owner} AS member_id,m.name,CONCAT_WS(' · ',l.title,l.area${kind === 'item' ? ',l.wanted' : ''}) AS content
    FROM ${table} l JOIN members m ON (m.community_id,m.id)=(l.community_id,l.${owner})
    WHERE l.community_id=? AND l.id=? AND l.withdrawn=FALSE
    ${kind === 'item' ? 'AND l.exchanged=0' : ''} FOR UPDATE`, [community, id])
  if (!listing) fail(404, 'content_not_found')
  if (actor.id === listing.member_id) fail(400, 'cannot_report_self')
  return { id, community, name: listing.name, content: listing.content, key: fingerprint(community, id) }
}

function chatEvidence(input: Input) {
  const id = boundedText(input.target_id, 128, 'invalid_content_id')
  const sender = boundedText(input.sender_id, 128, 'invalid_sender')
  const name = boundedText(input.sender_name, 200, 'invalid_sender')
  const content = boundedText(input.content, 4000, 'invalid_content')
  return { id, community: null, name, content, key: chatFingerprint(id, sender, content), senderKey: chatSenderKey(sender) }
}

export async function reportContent(db: PoolConnection, actor: Actor, input: Input) {
  const { kind } = input
  if (kind !== 'post' && kind !== 'item' && kind !== 'chat') fail(400, 'invalid_report_kind')
  const reason = boundedText(input.reason, 500, 'reason_required')
  const evidence = kind === 'chat' ? chatEvidence(input) : await listingEvidence(db, actor, kind, input)
  const senderKey = 'senderKey' in evidence ? evidence.senderKey : null
  if (senderKey) {
    // Coordinate with erasure so a report cannot restore the deleted message text.
    const [sender] = await rows<{ member_id: string | null }>(db,
      'SELECT member_id FROM member_chat_identities WHERE sender_key=? FOR UPDATE', [senderKey])
    if ((sender && sender.member_id === null) || (await removedChatKeys(db, [evidence.key])).length) return { ok: true }
  }
  // Use the original district to deduplicate after the reporter changes districts.
  const [member] = await rows<{ origin: string }>(db, 'SELECT COALESCE(origin_community_id, community_id) AS origin FROM members WHERE community_id=? AND id=?',
    [actor.community_id, actor.id])
  if (!member) fail(401, 'invalid_token')
  await db.execute(`INSERT INTO content_reports
    (id,kind,target_key,target_id,target_community_id,target_name,content,reporter_community_id,reporter_id,reason,chat_sender_key)
    VALUES (?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE id=id`,
  [randomUUID(), kind, evidence.key, evidence.id, evidence.community, evidence.name, evidence.content, member.origin, actor.id, reason, senderKey])
  return { ok: true }
}

export async function reportQueue(db: Db, actor: Actor) {
  const districts = listingScope(actor)
  return rows(db, `SELECT r.id,r.kind,r.target_name,r.content,r.reason,r.state,r.resolution_reason,r.created_at,r.resolved_at,
    c.name AS district,m.name AS reporter_name
    FROM content_reports r
    LEFT JOIN communities c ON c.id=r.target_community_id
    LEFT JOIN members m ON (m.community_id,m.id)=(r.reporter_community_id,r.reporter_id)
    WHERE r.target_community_id IS NULL OR r.target_community_id IN (${districts.map(() => '?').join(',')})
    ORDER BY (r.state='pending') DESC,r.created_at DESC,r.id LIMIT 100`, districts)
}

export async function resolveReport(db: PoolConnection, actor: Actor, id: string, input: Input) {
  const { outcome } = input
  if (outcome !== 'dismissed' && outcome !== 'removed') fail(400, 'invalid_report_outcome')
  const reason = boundedText(input.reason, 500, 'reason_required')
  const [report] = await rows<Report>(db, 'SELECT * FROM content_reports WHERE id=? FOR UPDATE', [uuid(id)])
  if (!report || (report.target_community_id && !listingScope(actor).includes(report.target_community_id))) fail(404, 'report_not_found')
  if (report.state === outcome) return { ok: true }
  if (report.state !== 'pending') fail(409, 'invalid_transition')
  if (outcome === 'removed' && report.kind !== 'chat') {
    const table = report.kind === 'post' ? 'help_posts' : 'items'
    await db.execute('UPDATE ' + table + ' SET withdrawn=TRUE WHERE community_id=? AND id=?',
      [report.target_community_id, report.target_id])
  }
  if (outcome === 'removed') {
    if (report.kind === 'chat') {
      await db.execute('INSERT INTO removed_chat_messages VALUES (?) ON DUPLICATE KEY UPDATE message_key=message_key',
        [report.target_key])
    }
    await db.execute("UPDATE content_reports SET state='removed',resolution_reason=?,resolved_at=UTC_TIMESTAMP(6) WHERE kind=? AND target_key=? AND state='pending'",
      [reason, report.kind, report.target_key])
  } else {
    await db.execute("UPDATE content_reports SET state='dismissed',resolution_reason=?,resolved_at=UTC_TIMESTAMP(6) WHERE id=?", [reason, report.id])
  }
  await audit(db, actor, 'content_report_' + outcome, report.id, reason)
  return { ok: true }
}
