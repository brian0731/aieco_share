import type { PoolConnection } from 'mysql2/promise'
import { rows, type Membership } from './database'
import { eraseMemberChat } from './member-chat'

export async function eraseMemberAccount(db: PoolConnection, member: Membership) {
  const origin = member.origin_community_id ?? member.community_id
  const memberships = await rows<{ community_id: string }>(db, `SELECT community_id FROM members
    WHERE id=? AND (community_id=? OR origin_community_id=?) ORDER BY community_id`, [member.id, origin, origin])
  await eraseMemberChat(db, member)
  await db.execute('DELETE FROM content_reports WHERE reporter_community_id=? AND reporter_id=?', [origin, member.id])
  for (const membership of memberships) {
    const key = [membership.community_id, member.id]
    await db.execute(`DELETE r FROM content_reports r
      LEFT JOIN help_posts p ON r.kind='post' AND (p.community_id,p.id)=(r.target_community_id,r.target_id)
      LEFT JOIN items i ON r.kind='item' AND (i.community_id,i.id)=(r.target_community_id,r.target_id)
      WHERE r.target_community_id=? AND (p.author_id=? OR i.owner_id=?)`, [...key, member.id])
    await db.execute(`UPDATE services SET state='cancelled' WHERE community_id=? AND (payer_id=? OR provider_id=?)
      AND state IN ('agreement','pending')`, [...key, member.id])
    await db.execute(`UPDATE items i JOIN exchanges e ON (e.community_id,e.id)=(i.community_id,i.reserved_by)
      SET i.reserved_by=NULL WHERE e.community_id=? AND (e.proposer_id=? OR e.owner_id=?) AND e.state='reserved'`, [...key, member.id])
    await db.execute(`UPDATE exchanges SET state=IF(state IN ('proposed','reserved'),'cancelled',state),meeting=''
      WHERE community_id=? AND (proposer_id=? OR owner_id=?)`, [...key, member.id])
    await db.execute('DELETE FROM ratings WHERE community_id=? AND (reviewer_id=? OR subject_id=?)', [...key, member.id])
    await db.execute('DELETE FROM disputes WHERE community_id=? AND reporter_id=?', key)
    await db.execute('DELETE FROM audit_log WHERE community_id=? AND actor_id=?', key)
    await db.execute('UPDATE time_journals SET reason=NULL WHERE community_id=? AND actor_id=?', key)
    await db.execute(`DELETE p FROM help_posts p LEFT JOIN services s ON (s.community_id,s.post_id)=(p.community_id,p.id)
      WHERE p.community_id=? AND p.author_id=? AND s.id IS NULL`, key)
    await db.execute(`DELETE i FROM items i
      LEFT JOIN exchanges o ON (o.community_id,o.offered_id)=(i.community_id,i.id)
      LEFT JOIN exchanges w ON (w.community_id,w.wanted_id)=(i.community_id,i.id)
      WHERE i.community_id=? AND i.owner_id=? AND o.id IS NULL AND w.id IS NULL`, key)
    await db.execute("UPDATE help_posts SET title='已刪除的貼文',area='',withdrawn=TRUE WHERE community_id=? AND author_id=?", key)
    await db.execute("UPDATE items SET title='已刪除的刊登',wanted='',area='',reserved_by=NULL,withdrawn=TRUE WHERE community_id=? AND owner_id=?", key)
    await db.execute('DELETE FROM member_credentials WHERE community_id=? AND member_id=?', key)
    await db.execute('DELETE FROM member_sessions WHERE community_id=? AND member_id=?', key)
    await db.execute("UPDATE members SET name='已刪除的用戶',account_state='deleted',token_hash=NULL WHERE community_id=? AND id=?", key)
  }
  const hasTrade = await rows(db, `SELECT id FROM members m WHERE m.id=?
    AND (m.community_id=? OR m.origin_community_id=?)
    AND (EXISTS (SELECT 1 FROM services s WHERE s.community_id=m.community_id AND m.id IN (s.payer_id,s.provider_id))
      OR EXISTS (SELECT 1 FROM exchanges e WHERE e.community_id=m.community_id AND m.id IN (e.proposer_id,e.owner_id))
      OR EXISTS (SELECT 1 FROM time_journals j WHERE (j.community_id,j.actor_id)=(m.community_id,m.id))
      OR EXISTS (SELECT 1 FROM time_entries e WHERE (e.community_id,e.member_id)=(m.community_id,m.id)))
    LIMIT 1`, [member.id, origin, origin])
  if (hasTrade.length) return
  for (const { community_id } of memberships) {
    await db.execute('DELETE FROM time_opening_credits WHERE community_id=? AND member_id=?', [community_id, member.id])
  }
  await db.execute('DELETE FROM members WHERE origin_community_id=? AND id=?', [origin, member.id])
  await db.execute('DELETE FROM members WHERE community_id=? AND id=?', [origin, member.id])
}
