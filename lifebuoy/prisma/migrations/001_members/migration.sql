CREATE TABLE communities (
  id VARCHAR(36) PRIMARY KEY,
  name VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE members (
  community_id VARCHAR(36) NOT NULL,
  id VARCHAR(36) NOT NULL,
  name VARCHAR(100) NOT NULL,
  role ENUM('member','admin') NOT NULL DEFAULT 'member',
  balance INT NOT NULL DEFAULT 0 CHECK (balance >= 0),
  token_hash BINARY(32) NOT NULL UNIQUE,
  PRIMARY KEY (community_id, id),
  FOREIGN KEY (community_id) REFERENCES communities(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE audit_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  community_id VARCHAR(36) NOT NULL,
  actor_id VARCHAR(36) NOT NULL,
  action VARCHAR(40) NOT NULL,
  target_id VARCHAR(36) NOT NULL,
  reason VARCHAR(500),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX (community_id, id),
  FOREIGN KEY (community_id, actor_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
