import { randomInt } from 'node:crypto'

export function normalizeRelay(value) {
  if (typeof value !== 'string' || value.includes('#')) return null
  const input = value.trim()
  if (!/^wss?:\/\/[^/]/i.test(input)) return null
  const url = URL.parse(input)
  if (!url?.hostname || url.username || url.password ||
      /[^\x21-\x7e]/.test(url.href) || url.href.length > 512) return null
  return url.href
}

export async function registerRelay(db, relay, draw = () => randomInt(1_000_000)) {
  const normalized = normalizeRelay(relay)
  if (!normalized) throw new Error('Invalid WebSocket relay URL')
  for (let attempt = 0; attempt < 32; attempt++) {
    const code = String(draw()).padStart(6, '0')
    try {
      await db.execute('INSERT INTO lightmesh_networks (code,relay) VALUES (?,?)', [code, normalized])
      return { code, relay: normalized }
    } catch (error) {
      if (error.code !== 'ER_DUP_ENTRY') throw error
      // A committed competing insert may already have registered the same URL.
      const [[existing]] = await db.execute('SELECT code FROM lightmesh_networks WHERE relay=?', [normalized])
      if (existing) return { code: existing.code, relay: normalized }
    }
  }
  throw new Error('Could not allocate a unique connection code')
}

export async function importRelay(db, code, relay) {
  const normalized = normalizeRelay(relay)
  if (typeof code !== 'string' || !/^[0-9]{6}$/.test(code) || !normalized) {
    throw new Error('Expected a six-digit code and a valid WebSocket relay URL')
  }
  try {
    await db.execute('INSERT INTO lightmesh_networks (code,relay) VALUES (?,?)', [code, normalized])
  } catch (error) {
    if (error.code !== 'ER_DUP_ENTRY') throw error
    const [[existing]] = await db.execute('SELECT relay FROM lightmesh_networks WHERE code=?', [code])
    if (existing?.relay !== normalized) {
      throw new Error('The code or relay URL is already assigned to another registration')
    }
  }
  return { code, relay: normalized }
}
