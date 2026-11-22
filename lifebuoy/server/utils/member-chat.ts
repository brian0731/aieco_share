import { randomUUID } from 'node:crypto'
import type { PoolConnection } from 'mysql2/promise'
import { boundedText, fail, rows, uuid, type Db, type Membership } from './database'
import { chatFingerprint, chatSenderKey, moderationKeys, removedChatKeys, requireAllowedContent } from './moderation'

const memberSender = /^lifebuoy-member-[a-f0-9-]{36}$/

export async function prepareMemberMessage(db: PoolConnection, member: Membership, input: Record<string, unknown>) {
  if (member.role !== 'member') fail(403, 'member_account_required')
  const messageId = uuid(input.message_id)
  const text = boundedText(input.text, 4000, 'invalid_content')
  requireAllowedContent(text)
  const owner = [member.origin_community_id ?? member.community_id, member.id]
  const newSender = 'lifebuoy-member-' + randomUUID()
  await db.execute(`INSERT INTO member_chat_identities (sender_key,sender_id,community_id,member_id)
    VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE sender_key=sender_key`, [chatSenderKey(newSender), newSender, ...owner])
  const [identity] = await rows<{ sender_key: string, sender_id: string }>(db,
    'SELECT sender_key,sender_id FROM member_chat_identities WHERE community_id=? AND member_id=? FOR UPDATE', owner)
  const fingerprint = chatFingerprint(messageId, identity.sender_id, text)
  await db.execute(`INSERT INTO member_chat_messages (sender_key,message_id,message_key)
    VALUES (?,?,?) ON DUPLICATE KEY UPDATE message_id=message_id`, [identity.sender_key, messageId, fingerprint])
  const [message] = await rows<{ message_key: string }>(db,
    'SELECT message_key FROM member_chat_messages WHERE sender_key=? AND message_id=?',
    [identity.sender_key, messageId])
  if (message.message_key !== fingerprint) fail(409, 'chat_id_conflict')
  return { sender_id: identity.sender_id }
}

export async function relayMayPublish(db: Db, sender: string, messageId: string, fingerprint: string) {
  if (!memberSender.test(sender)) return true
  const [message] = await rows(db, `SELECT 1 FROM member_chat_messages
    WHERE sender_key=? AND message_id=? AND message_key=?`,
  [chatSenderKey(sender), messageId, fingerprint])
  return Boolean(message)
}

export async function removedSenderKeys(db: Db, keys: string[]) {
  if (!keys.length) return []
  const records = await rows<{ sender_key: string }>(db, `SELECT sender_key FROM member_chat_identities
    WHERE member_id IS NULL AND sender_key IN (${keys.map(() => '?').join(',')})`, keys)
  return records.map(row => row.sender_key)
}

export async function checkChatModeration(db: Db, input: Record<string, unknown>) {
  const keys = moderationKeys(input.keys)
  const senders = moderationKeys(input.senders ?? [])
  const [removed, removedSenders] = await Promise.all([removedChatKeys(db, keys), removedSenderKeys(db, senders)])
  return { removed, removed_senders: removedSenders }
}

export async function eraseMemberChat(db: PoolConnection, member: Membership) {
  const owner = [member.origin_community_id ?? member.community_id, member.id]
  const [identity] = await rows<{ sender_key: string }>(db,
    'SELECT sender_key FROM member_chat_identities WHERE community_id=? AND member_id=? FOR UPDATE', owner)
  if (!identity) return
  const keys = [identity.sender_key]
  await db.execute('DELETE FROM member_chat_messages WHERE sender_key=?', keys)
  await db.execute('DELETE FROM content_reports WHERE chat_sender_key=?', keys)
  // Keep only the opaque sender digest so peers can purge previously delivered messages.
  await db.execute('UPDATE member_chat_identities SET sender_id=NULL,community_id=NULL,member_id=NULL WHERE sender_key=?', keys)
}
