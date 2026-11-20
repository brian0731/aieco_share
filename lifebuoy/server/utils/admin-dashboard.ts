import { rows, type Actor, type Db } from './database'

export async function adminDashboard(db: Db, actor: Actor) {
  const scope = [actor.community_id]
  const [[community], members, services, ledger, items, exchanges, disputes, audit] = await Promise.all([
    rows<{ name: string }>(db, 'SELECT name FROM communities WHERE id=?', scope),
    rows(db, 'SELECT id,name,role,balance FROM members WHERE community_id=? ORDER BY name,id LIMIT 100', scope),
    rows(db, `SELECT s.*,p.title,p.area,p.created_at,payer.name AS payer_name,provider.name AS provider_name
      FROM services s JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
      JOIN members payer ON (payer.community_id,payer.id)=(s.community_id,s.payer_id)
      JOIN members provider ON (provider.community_id,provider.id)=(s.community_id,s.provider_id)
      WHERE s.community_id=? ORDER BY p.created_at DESC,s.id DESC LIMIT 100`, scope),
    rows(db, `SELECT j.*,p.title,m.name AS actor_name,s.minutes
      FROM time_journals j JOIN services s ON (s.community_id,s.id)=(j.community_id,j.service_id)
      JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
      JOIN members m ON (m.community_id,m.id)=(j.community_id,j.actor_id)
      WHERE j.community_id=? ORDER BY j.created_at DESC,j.service_id,j.kind LIMIT 100`, scope),
    rows(db, `SELECT i.*,m.name AS owner_name FROM items i
      JOIN members m ON (m.community_id,m.id)=(i.community_id,i.owner_id)
      WHERE i.community_id=? ORDER BY i.created_at DESC,i.id DESC LIMIT 100`, scope),
    rows(db, `SELECT e.id,e.offered_id,e.wanted_id,e.proposer_id,e.owner_id,e.meeting,e.state,e.expires_at,
      e.completed_at,e.expires_at<=UTC_TIMESTAMP(6) AS expired,
      offered.title AS offered_title,wanted.title AS wanted_title,p.name AS proposer_name,o.name AS owner_name
      FROM exchanges e JOIN items offered ON (offered.community_id,offered.id)=(e.community_id,e.offered_id)
      JOIN items wanted ON (wanted.community_id,wanted.id)=(e.community_id,e.wanted_id)
      JOIN members p ON (p.community_id,p.id)=(e.community_id,e.proposer_id)
      JOIN members o ON (o.community_id,o.id)=(e.community_id,e.owner_id)
      WHERE e.community_id=? ORDER BY COALESCE(e.completed_at,e.expires_at) DESC,e.id DESC LIMIT 100`, scope),
    rows(db, `SELECT d.*,m.name AS reporter_name,
      COALESCE(p.title, CONCAT(o.title,' ⇄ ',w.title)) AS trade_title
      FROM disputes d JOIN members m ON (m.community_id,m.id)=(d.community_id,d.reporter_id)
      LEFT JOIN services s ON d.kind='service' AND (s.community_id,s.id)=(d.community_id,d.trade_id)
      LEFT JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
      LEFT JOIN exchanges e ON d.kind='exchange' AND (e.community_id,e.id)=(d.community_id,d.trade_id)
      LEFT JOIN items o ON (o.community_id,o.id)=(e.community_id,e.offered_id)
      LEFT JOIN items w ON (w.community_id,w.id)=(e.community_id,e.wanted_id)
      WHERE d.community_id=? ORDER BY d.outcome IS NULL DESC,d.created_at DESC,d.trade_id LIMIT 100`, scope),
    rows(db, `SELECT a.*,m.name AS actor_name,
      COALESCE(p.title, CONCAT(o.title,' ⇄ ',w.title)) AS target_title
      FROM audit_log a JOIN members m ON (m.community_id,m.id)=(a.community_id,a.actor_id)
      LEFT JOIN services s ON (s.community_id,s.id)=(a.community_id,a.target_id)
      LEFT JOIN help_posts p ON (p.community_id,p.id)=(s.community_id,s.post_id)
      LEFT JOIN exchanges e ON (e.community_id,e.id)=(a.community_id,a.target_id)
      LEFT JOIN items o ON (o.community_id,o.id)=(e.community_id,e.offered_id)
      LEFT JOIN items w ON (w.community_id,w.id)=(e.community_id,e.wanted_id)
      WHERE a.community_id=? ORDER BY a.id DESC LIMIT 100`, scope),
  ])
  return { community: community?.name, members, services, ledger, items, exchanges, disputes, audit }
}
