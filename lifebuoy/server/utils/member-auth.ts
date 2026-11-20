import { createHash, randomBytes, randomUUID, scrypt, timingSafeEqual } from 'node:crypto'
import { promisify } from 'node:util'
import type { H3Event } from 'h3'
import type { Pool } from 'mysql2/promise'
import { boundedText, fail, rows, transaction, type Db } from './database'
import { requiredDistrict } from './districts'

const derive = promisify(scrypt)
const unknownSalt = randomBytes(16)
const attempts = new Map<string, { count: number; reset: number }>()
const windowMs = 60_000
const openingMinutes = 60
let activeHashes = 0

export function loginRateLimit(event: H3Event) {
  const key = event.node.req.socket.remoteAddress ?? 'unknown'
  const now = Date.now()
  let attempt = attempts.get(key)
  if (!attempt || attempt.reset <= now) {
    if (attempts.size >= 4096) {
      for (const [address, value] of attempts) {
        if (value.reset <= now) attempts.delete(address)
      }
      if (attempts.size >= 4096) fail(429, 'try_again_later')
    }
    attempt = { count: 0, reset: now + windowMs }
    attempts.set(key, attempt)
  }
  if (++attempt.count > 12) {
    setResponseHeader(event, 'Retry-After', String(Math.ceil((attempt.reset - now) / 1000)))
    fail(429, 'try_again_later')
  }
}

async function passwordHash(password: string, salt: Buffer) {
  if (activeHashes >= 4) fail(429, 'try_again_later')
  activeHashes++
  try {
    return await derive(password, salt, 64, { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 }) as Buffer
  } finally {
    activeHashes--
  }
}

function credentials(input: Record<string, unknown>, registering: boolean) {
  const username = typeof input.username === 'string' ? input.username.trim().toLowerCase() : ''
  const password = input.password
  if (!/^[a-z0-9_]{3,32}$/.test(username)) fail(400, 'invalid_username')
  if (typeof password !== 'string' || password.length < 12 || Buffer.byteLength(password) > 256) {
    fail(registering ? 400 : 401, registering ? 'invalid_password' : 'incorrect_credentials')
  }
  return { username, password }
}

async function issueSession(db: Db, community: string, member: string) {
  const token = randomBytes(32).toString('base64url')
  const digest = createHash('sha256').update(token).digest()
  await db.execute(
    'DELETE FROM member_sessions WHERE community_id=? AND member_id=? AND expires_at<=UTC_TIMESTAMP(6)',
    [community, member],
  )
  await db.execute(
    'INSERT INTO member_sessions VALUES (?,?,?,UTC_TIMESTAMP(6)+INTERVAL 7 DAY)',
    [digest, community, member],
  )
  return { token }
}

export async function registerMember(db: Pool, input: Record<string, unknown>) {
  const community = requiredDistrict(input.community_id)
  const { username, password } = credentials(input, true)
  const name = boundedText(input.name, 100, 'invalid_name')
  const id = randomUUID()
  const salt = randomBytes(16)
  const hash = await passwordHash(password, salt)
  try {
    return await transaction(db, async conn => {
      const [tenant] = await rows(conn, 'SELECT id FROM communities WHERE id=?', [community])
      if (!tenant) fail(503, 'registration_unavailable')
      await conn.execute(
        'INSERT INTO members (community_id,id,name,balance) VALUES (?,?,?,?)',
        [community, id, name, openingMinutes],
      )
      await conn.execute(
        'INSERT INTO member_credentials (username,community_id,member_id,password_salt,password_hash) VALUES (?,?,?,?,?)',
        [username, community, id, salt, hash],
      )
      await conn.execute(
        'INSERT INTO time_opening_credits (community_id,member_id,minutes,applied_at) VALUES (?,?,?,UTC_TIMESTAMP(6))',
        [community, id, openingMinutes],
      )
      return issueSession(conn, community, id)
    })
  } catch (error) {
    if ((error as { code?: string }).code === 'ER_DUP_ENTRY') fail(409, 'username_taken')
    throw error
  }
}

export async function loginMember(db: Pool, input: Record<string, unknown>) {
  const { username, password } = credentials(input, false)
  const [member] = await rows<{
    community_id: string
    member_id: string
    password_salt: Buffer
    password_hash: Buffer
  }>(db, 'SELECT community_id,member_id,password_salt,password_hash FROM member_credentials WHERE username=?', [username])
  const hash = await passwordHash(password, member?.password_salt ?? unknownSalt)
  if (!member || !timingSafeEqual(hash, member.password_hash)) fail(401, 'incorrect_credentials')
  return issueSession(db, member.community_id, member.member_id)
}
