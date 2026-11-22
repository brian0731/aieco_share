import { createHash } from 'node:crypto'
import type { H3Event } from 'h3'
import mysql, { type Pool, type PoolConnection, type RowDataPacket } from 'mysql2/promise'

export type Db = Pool | PoolConnection
export type Actor = { id: string; community_id: string; role: 'member' | 'admin' }
export type Membership = Actor & {
  origin_community_id: string | null
  account_state: 'active' | 'moved' | 'deleted'
  name: string
}
let pool: Pool | undefined

export function database(event?: H3Event) {
  const { databaseUrl } = useRuntimeConfig(event)
  if (!databaseUrl) fail(503, 'database_unavailable')
  return pool ??= mysql.createPool({ uri: databaseUrl, connectionLimit: 10, timezone: 'Z' })
}

export function fail(statusCode: number, statusMessage: string): never {
  throw createError({ statusCode, statusMessage })
}

export async function rows<T>(db: Db, sql: string, args: unknown[] = []) {
  const [result] = await db.execute<(T & RowDataPacket)[]>(sql, args)
  return result as T[]
}

export async function authenticate(event: H3Event, db: Db) {
  setResponseHeader(event, 'Cache-Control', 'no-store')
  const digest = bearerDigest(event)
  const [session] = await rows<Actor>(db, `SELECT m.id,m.community_id,m.role
    FROM member_sessions s JOIN members m ON (m.community_id,m.id)=(s.community_id,s.member_id)
    WHERE s.token_hash=? AND s.expires_at>UTC_TIMESTAMP(6) AND m.account_state='active'`, [digest])
  if (session) return session
  const [actor] = await rows<Actor>(db, "SELECT id,community_id,role FROM members WHERE token_hash=? AND account_state='active'", [digest])
  if (!actor) fail(401, 'invalid_token')
  return actor
}

export async function lockMembership(db: PoolConnection, actor: Actor) {
  const [member] = await rows<Membership>(db,
    'SELECT id,community_id,role,name,origin_community_id,account_state FROM members WHERE community_id=? AND id=? FOR UPDATE',
    [actor.community_id, actor.id])
  if (!member || member.account_state !== 'active') fail(401, 'invalid_token')
  return member
}

export async function memberDistricts(db: Db, actor: Actor) {
  const [member] = await rows<{ origin: string }>(db,
    'SELECT COALESCE(origin_community_id,community_id) AS origin FROM members WHERE community_id=? AND id=?',
    [actor.community_id, actor.id])
  if (!member) fail(401, 'invalid_token')
  const history = await rows<{ community_id: string }>(db,
    'SELECT community_id FROM members WHERE id=? AND origin_community_id=?', [actor.id, member.origin])
  return { origin: member.origin, districts: [member.origin, ...history.map(row => row.community_id)] }
}

export function bearerDigest(event: H3Event) {
  const token = getHeader(event, 'authorization')?.match(/^Bearer ([A-Za-z0-9_-]{32,128})$/i)?.[1]
  if (!token) fail(401, 'token_required')
  return createHash('sha256').update(token).digest()
}

export async function jsonInput(event: H3Event, maxBytes = 8192): Promise<Record<string, unknown>> {
  if (getHeader(event, 'content-type')?.split(';')[0].trim() !== 'application/json') {
    fail(415, 'json_required')
  }
  let size = 0
  const chunks: Buffer[] = []
  for await (const chunk of event.node.req.iterator({ destroyOnReturn: false })) {
    size += chunk.length
    if (size > maxBytes) {
      event.node.req.resume()
      fail(413, 'body_too_large')
    }
    chunks.push(chunk)
  }
  let input: unknown
  try {
    input = JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    fail(400, 'invalid_json')
  }
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail(400, 'invalid_body')
  return input as Record<string, unknown>
}

export async function transaction<T>(db: Pool, work: (conn: PoolConnection) => Promise<T>) {
  const conn = await db.getConnection()
  try {
    await conn.beginTransaction()
    const result = await work(conn)
    await conn.commit()
    return result
  } catch (error) {
    try {
      await conn.rollback()
    } catch {
      conn.destroy()
    }
    if ((error as { code?: string }).code === 'ER_LOCK_DEADLOCK' ||
        (error as { code?: string }).code === 'ER_LOCK_WAIT_TIMEOUT') {
      fail(503, 'retry_transaction')
    }
    throw error
  } finally {
    conn.release()
  }
}

export function audit(db: Db, actor: Actor, action: string, id: string, reason?: string) {
  return db.execute(
    'INSERT INTO audit_log (community_id, actor_id, action, target_id, reason) VALUES (?,?,?,?,?)',
    [actor.community_id, actor.id, action, id, reason ?? null],
  )
}

export function boundedText(value: unknown, max: number, error: string) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail(400, error)
  return value.trim()
}

export function uuid(value: unknown) {
  if (typeof value !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value)) fail(400, 'invalid_id')
  return value
}

export function minutes(value: unknown) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 1440) {
    fail(400, 'invalid_minutes')
  }
  return value
}
