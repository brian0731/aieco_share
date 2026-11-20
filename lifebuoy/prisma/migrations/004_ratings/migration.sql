CREATE TABLE disputes (
  community_id VARCHAR(36) NOT NULL,
  kind ENUM('service','exchange') NOT NULL,
  trade_id CHAR(36) NOT NULL,
  reporter_id VARCHAR(36) NOT NULL,
  reason VARCHAR(500) NOT NULL,
  outcome ENUM('restore','exclude'),
  resolution_reason VARCHAR(500),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (community_id,kind,trade_id),
  FOREIGN KEY (community_id,reporter_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ratings (
  community_id VARCHAR(36) NOT NULL,
  kind ENUM('service','exchange') NOT NULL,
  trade_id CHAR(36) NOT NULL,
  reviewer_id VARCHAR(36) NOT NULL,
  subject_id VARCHAR(36) NOT NULL,
  stars TINYINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (community_id,kind,trade_id,reviewer_id),
  INDEX (community_id,subject_id,reviewer_id),
  FOREIGN KEY (community_id,reviewer_id) REFERENCES members(community_id,id),
  FOREIGN KEY (community_id,subject_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
