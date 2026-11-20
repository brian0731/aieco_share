CREATE TABLE items (
  community_id VARCHAR(36) NOT NULL,
  id CHAR(36) NOT NULL,
  owner_id VARCHAR(36) NOT NULL,
  title VARCHAR(120) NOT NULL,
  wanted VARCHAR(120) NOT NULL,
  area VARCHAR(80) NOT NULL,
  reserved_by CHAR(36),
  exchanged BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (community_id,id),
  FOREIGN KEY (community_id,owner_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exchanges (
  community_id VARCHAR(36) NOT NULL,
  id CHAR(36) NOT NULL,
  offered_id CHAR(36) NOT NULL,
  wanted_id CHAR(36) NOT NULL,
  proposer_id VARCHAR(36) NOT NULL,
  owner_id VARCHAR(36) NOT NULL,
  meeting VARCHAR(200) NOT NULL,
  state ENUM('proposed','reserved','completed','cancelled') NOT NULL DEFAULT 'proposed',
  expires_at DATETIME(6),
  proposer_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  owner_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at DATETIME(6),
  PRIMARY KEY (community_id,id),
  CHECK (offered_id <> wanted_id AND proposer_id <> owner_id),
  FOREIGN KEY (community_id,offered_id) REFERENCES items(community_id,id),
  FOREIGN KEY (community_id,wanted_id) REFERENCES items(community_id,id),
  FOREIGN KEY (community_id,proposer_id) REFERENCES members(community_id,id),
  FOREIGN KEY (community_id,owner_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
