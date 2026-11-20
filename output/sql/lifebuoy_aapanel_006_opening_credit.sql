-- Select the existing Lifebuoy database in aaPanel before importing.
-- Requires migrations 001 through 005. May be imported again safely.

CREATE TABLE IF NOT EXISTS time_opening_credits (
  community_id VARCHAR(36) NOT NULL,
  member_id VARCHAR(36) NOT NULL,
  minutes SMALLINT UNSIGNED NOT NULL CHECK (minutes > 0),
  applied_at DATETIME(6),
  PRIMARY KEY (community_id, member_id),
  FOREIGN KEY (community_id, member_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO time_opening_credits (community_id, member_id, minutes)
SELECT c.community_id, c.member_id, 60
FROM member_credentials c
JOIN members m ON (m.community_id, m.id) = (c.community_id, c.member_id)
WHERE m.role = 'member'
ON DUPLICATE KEY UPDATE minutes = time_opening_credits.minutes;

UPDATE members m
JOIN time_opening_credits credit ON (credit.community_id, credit.member_id) = (m.community_id, m.id)
SET m.balance = m.balance + credit.minutes, credit.applied_at = UTC_TIMESTAMP(6)
WHERE credit.applied_at IS NULL;

INSERT INTO lifebuoy_migrations (version, checksum)
VALUES ('006_opening_credit.sql', 'aafb37dd7887ae4a422d387bd9f11ee65e28545ccd3bd01a536e64980ae087db')
ON DUPLICATE KEY UPDATE version = lifebuoy_migrations.version;
