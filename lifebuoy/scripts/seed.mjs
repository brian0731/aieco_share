import { createHash, randomBytes } from 'node:crypto'
import mysql from 'mysql2/promise'

const url = process.env.NUXT_DATABASE_URL
if (!url || new URL(url).hostname !== '127.0.0.1' || !/^\/lifebuoy_(dev|test)$/.test(new URL(url).pathname)) {
  throw new Error('Seed requires a dedicated loopback database named lifebuoy_dev or lifebuoy_test')
}
const db = await mysql.createConnection(url)
try {
  const [[{ version }]] = await db.query('SELECT VERSION() AS version')
  if (!/^8\.4\./.test(version)) throw new Error('MySQL 8.4 is required')
  await db.beginTransaction()
  await db.execute("INSERT INTO communities VALUES ('demo','社區救生圈驗收') ON DUPLICATE KEY UPDATE id=id")
  const issued = []
  for (const [id, name, role, balance] of [
    ['alice','阿晴','member',60],
    ['bob','阿朗','member',0],
    ['admin','社區協調員','admin',0],
    ['new','新成員','member',0],
  ]) {
    const token = randomBytes(32).toString('base64url')
    const hash = createHash('sha256').update(token).digest()
    await db.execute(
      `INSERT INTO members (community_id,id,name,role,balance,token_hash) VALUES ('demo',?,?,?,?,?)
       ON DUPLICATE KEY UPDATE token_hash=?`, [id, name, role, balance, hash, hash],
    )
    issued.push({ id, name, token })
  }
  await db.commit()
  console.log(JSON.stringify(issued, null, 2))
} catch (error) {
  await db.rollback()
  throw error
} finally {
  await db.end()
}
