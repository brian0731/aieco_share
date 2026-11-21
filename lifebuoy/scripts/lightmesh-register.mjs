import 'dotenv/config'
import mysql from 'mysql2/promise'
import { importRelay, normalizeRelay, registerRelay } from '../shared/lightmesh-registry.mjs'

async function main() {
  const dbUrl = URL.parse(process.env.NUXT_DATABASE_URL ?? '')
  const [url, option, code, ...extra] = process.argv.slice(2)
  const relay = normalizeRelay(url)
  const validOptions = option === undefined || (option === '--existing-code' && /^[0-9]{6}$/.test(code ?? '') && !extra.length)
  if (!dbUrl || dbUrl.protocol !== 'mysql:' || !dbUrl.pathname.slice(1) || !relay || !validOptions) {
    throw new Error('Set NUXT_DATABASE_URL and run npm run lightmesh:register -- <ws-or-wss-url> [--existing-code <six-digit-code>]')
  }
  dbUrl.searchParams.delete('timezone')
  const db = await mysql.createConnection({ uri: dbUrl.href, connectTimeout: 8000 })
  try {
    const result = option
      ? await importRelay(db, code, relay)
      : await registerRelay(db, relay)
    console.log(JSON.stringify(result))
  } finally {
    await db.end()
  }
}

main().catch(error => {
  console.error('Lightmesh registration failed:', error.code ?? error.message)
  process.exitCode = 1
})
