ALTER TABLE members MODIFY token_hash BINARY(32) NULL;

CREATE TABLE member_credentials (
  username VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  community_id VARCHAR(36) NOT NULL,
  member_id VARCHAR(36) NOT NULL,
  password_salt BINARY(16) NOT NULL,
  password_hash BINARY(64) NOT NULL,
  UNIQUE (community_id,member_id),
  FOREIGN KEY (community_id,member_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE member_sessions (
  token_hash BINARY(32) PRIMARY KEY,
  community_id VARCHAR(36) NOT NULL,
  member_id VARCHAR(36) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  INDEX (community_id,member_id,expires_at),
  FOREIGN KEY (community_id,member_id) REFERENCES members(community_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO communities (id,name) VALUES ('demo','社區救生圈驗收')
ON DUPLICATE KEY UPDATE id=id;
