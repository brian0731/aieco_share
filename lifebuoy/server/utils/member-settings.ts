import { randomBytes } from 'node:crypto'
import type { PoolConnection } from 'mysql2/promise'
import { boundedText, fail, rows, type Membership } from './database'
import { eraseMemberAccount } from './account-erasure'
import { requiredDistrict } from './districts'
import { passwordHash, validPassword, verifyCurrentPassword } from './member-auth'

type Input = Record<string, unknown>

export async function changeMemberSettings(db: PoolConnection, member: Membership, action: string, input: Input) {
  const current = [member.community_id, member.id]
  const origin = member.origin_community_id ?? member.community_id
  const identity = [member.id, origin, origin]
  const membershipScope = 'id=? AND (community_id=? OR origin_community_id=?)'

  if (action === 'profile') {
    const name = boundedText(input.name, 100, 'invalid_name')
    const district = requiredDistrict(input.community_id)
    const [credential] = await rows(db,
      'SELECT username FROM member_credentials WHERE community_id=? AND member_id=?', current)
    if (!credential || member.role !== 'member') fail(403, 'member_account_required')
    if (district !== member.community_id) {
      const [destination] = await rows<{ origin_community_id: string | null, account_state: string }>(db,
        'SELECT origin_community_id,account_state FROM members WHERE community_id=? AND id=? FOR UPDATE',
        [district, member.id])
      if (destination && (destination.account_state !== 'moved' || (destination.origin_community_id ?? district) !== origin)) {
        fail(409, 'district_conflict')
      }
      if (!destination) {
        await db.execute("INSERT INTO members (community_id,id,name,origin_community_id) VALUES (?,?,?,?)",
          [district, member.id, name, origin])
      } else {
        await db.execute("UPDATE members SET account_state='active' WHERE community_id=? AND id=?", [district, member.id])
      }
      await db.execute("UPDATE members SET account_state='moved' WHERE community_id=? AND id=?", current)
      await withdrawListings(db, member)
      await db.execute('UPDATE member_credentials SET community_id=? WHERE community_id=? AND member_id=?', [district, ...current])
      await db.execute('UPDATE member_sessions SET community_id=? WHERE community_id=? AND member_id=?', [district, ...current])
    }
    await db.execute(`UPDATE members SET name=? WHERE ${membershipScope}`, [name, ...identity])
    return { name, community_id: district }
  }

  if (action !== 'password' && action !== 'delete') fail(404, 'unknown_action')
  if (member.role !== 'member') fail(403, 'member_account_required')
  await verifyCurrentPassword(db, member, input.current_password)
  if (action === 'delete') {
    await eraseMemberAccount(db, member)
    return { ok: true }
  }
  if (!validPassword(input.new_password)) fail(400, 'invalid_password')
  const salt = randomBytes(16)
  const hash = await passwordHash(input.new_password, salt)
  await db.execute('UPDATE member_credentials SET password_salt=?,password_hash=? WHERE community_id=? AND member_id=?',
    [salt, hash, ...current])
  await db.execute('DELETE FROM member_sessions WHERE community_id=? AND member_id=?', current)
  return { ok: true }
}

async function withdrawListings(db: PoolConnection, member: { community_id: string, id: string }) {
  const key = [member.community_id, member.id]
  await db.execute('UPDATE help_posts SET withdrawn=TRUE WHERE community_id=? AND author_id=? AND withdrawn=FALSE', key)
  await db.execute('UPDATE items SET withdrawn=TRUE WHERE community_id=? AND owner_id=? AND withdrawn=FALSE', key)
}
