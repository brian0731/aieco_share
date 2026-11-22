CREATE TABLE content_reports (
  id VARCHAR(36) PRIMARY KEY,
  kind ENUM('post','item','chat') NOT NULL,
  target_key CHAR(64) NOT NULL,
  target_id VARCHAR(128) NOT NULL,
  target_community_id VARCHAR(36),
  target_name VARCHAR(200) NOT NULL,
  content TEXT NOT NULL,
  reporter_community_id VARCHAR(36) NOT NULL,
  reporter_id VARCHAR(36) NOT NULL,
  reason VARCHAR(500) NOT NULL,
  state ENUM('pending','dismissed','removed') NOT NULL DEFAULT 'pending',
  resolution_reason VARCHAR(500),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  resolved_at DATETIME(6),
  UNIQUE KEY unique_report (reporter_community_id, reporter_id, kind, target_key),
  KEY report_target (kind, target_key, state),
  KEY report_queue (state, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
