import 'dotenv/config'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readdir, readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import mysql from 'mysql2/promise'

const require = createRequire(import.meta.url)
const prisma = require.resolve('prisma/build/index.js')
const url = new URL(process.env.NUXT_DATABASE_URL || 'about:blank')
if (url.protocol !== 'mysql:' || !url.pathname.slice(1)) {
  throw new Error('Set NUXT_DATABASE_URL to a MySQL URL with an explicit database name')
}
// This connection reads migration metadata and holds the lock. It does not read timestamps.
url.searchParams.delete('timezone')

const migrationDir = new URL('../prisma/migrations/', import.meta.url)
const migrations = (await readdir(migrationDir, { withFileTypes: true }))
  .filter(entry => entry.isDirectory()).map(entry => entry.name).sort()
const originalTables = new Map([
  ['001_members', ['communities', 'members', 'audit_log']],
  ['002_time_bank', ['help_posts', 'services', 'time_journals', 'time_entries']],
  ['003_exchange', ['items', 'exchanges']],
  ['004_ratings', ['disputes', 'ratings']],
  ['005_member_auth', ['member_credentials', 'member_sessions']],
])

function migrate(...args) {
  const result = spawnSync(process.execPath, [prisma, 'migrate', ...args], { stdio: 'inherit' })
  if (result.error) throw result.error
  if (result.status !== 0) throw new Error(`Prisma migrate ${args[0]} failed`)
}

const db = await mysql.createConnection({ uri: url.href, connectTimeout: 8000 })
try {
  const [[{ version, name }]] = await db.query('SELECT VERSION() AS version, DATABASE() AS name')
  const maria = /MariaDB/i.test(version)
  const numbers = (maria ? version.replace(/^5\.5\.5-/, '') : version).match(/^(\d+)\.(\d+)\.(\d+)/)
  const [major, minor, patch] = (numbers?.slice(1) ?? []).map(Number)
  // The time bank relies on enforced CHECK constraints.
  const supported = maria
    ? (major === 10 && minor >= 4) || major === 11
    : major === 8 && (minor === 4 || (minor === 0 && patch >= 16))
  console.log(`Database: ${name ?? '(none)'} (${version})`)
  if (!name || !supported) {
    throw new Error('Select a database on MySQL 8.0.16 or later in 8.0, MySQL 8.4, or MariaDB 10.4–11.x')
  }
  const [[{ locked }]] = await db.execute('SELECT GET_LOCK(SHA2(?, 256), 10) AS locked', [`lifebuoy:${name}`])
  if (locked !== 1) throw new Error('Could not acquire migration lock')

  const [tables] = await db.query(`
    SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
  `)
  const tableNames = new Set(tables.map(table => table.name))
  const [legacy] = tableNames.has('lifebuoy_migrations')
    ? await db.query('SELECT version, checksum FROM lifebuoy_migrations ORDER BY version')
    : [[]]
  const [applied] = tableNames.has('_prisma_migrations')
    ? await db.query('SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL')
    : [[]]
  const completed = new Set(applied.map(row => row.migration_name))
  const adopted = new Set()
  for (const [index, row] of legacy.entries()) {
    const name = migrations[index]
    if (!name || row.version !== `${name}.sql` || !/^00[1-8]_/.test(name)) {
      throw new Error(`Unexpected legacy migration history at ${row.version}`)
    }
    const sql = await readFile(new URL(`${name}/migration.sql`, migrationDir), 'utf8')
    const checksum = createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex')
    if (checksum !== row.checksum) throw new Error(`Legacy checksum mismatch: ${row.version}`)
    adopted.add(name)
  }

  for (const [name, expected] of originalTables) {
    const present = expected.filter(table => tableNames.has(table))
    const recorded = completed.has(name) || adopted.has(name)
    if ((recorded && present.length !== expected.length) || (!recorded && present.length > 0)) {
      throw new Error(`Schema and migration history disagree for ${name}. Check the existing tables and migration records before retrying.`)
    }
  }
  for (const name of adopted) {
    if (!completed.has(name)) migrate('resolve', '--applied', name)
  }
  migrate('deploy')
} finally {
  await db.end()
}
