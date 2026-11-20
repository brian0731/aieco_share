-- Select the existing Lifebuoy database in aaPanel before importing.
-- Apply 006 before this script.
-- Adds the opening credit to legacy regular members without a preloaded balance.
-- Repeat imports do not add minutes twice.

INSERT INTO time_opening_credits (community_id, member_id, minutes)
SELECT m.community_id, m.id, 60
FROM members m
LEFT JOIN (
  SELECT community_id, member_id, SUM(delta) AS net_minutes
  FROM time_entries
  GROUP BY community_id, member_id
) history ON (history.community_id, history.member_id) = (m.community_id, m.id)
WHERE m.role = 'member'
  AND m.balance = COALESCE(history.net_minutes, 0)
ON DUPLICATE KEY UPDATE minutes = time_opening_credits.minutes;

UPDATE members m
JOIN time_opening_credits credit ON (credit.community_id, credit.member_id) = (m.community_id, m.id)
SET m.balance = m.balance + credit.minutes, credit.applied_at = UTC_TIMESTAMP(6)
WHERE credit.applied_at IS NULL;

INSERT INTO lifebuoy_migrations (version, checksum)
VALUES ('007_existing_member_opening_credit.sql', '0de8feaea359fb614856c9a6305910abbd3c003600905d184e84a03e81520e0d')
ON DUPLICATE KEY UPDATE version = lifebuoy_migrations.version;

