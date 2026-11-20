-- Community Lifebuoy bootstrap for MySQL 8.4.
-- Import once on a fresh server database. Stop on the first SQL error.
-- For a pre-created empty database, skip CREATE DATABASE and update USE.
-- No database accounts, application users, or passwords are included.
SET NAMES utf8mb4;
CREATE DATABASE `lifebuoy` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE `lifebuoy`;

CREATE TABLE lifebuoy_migrations (
  version VARCHAR(100) PRIMARY KEY,
  checksum CHAR(64) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 001_members.sql
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

INSERT INTO lifebuoy_migrations (version, checksum) VALUES ('001_members.sql', '26cc9e1488da4ec8d37d22ba13d058624d0d24cf2da897bd48e49c24d40d4f7e');

-- 002_time_bank.sql
CREATE TABLE help_posts (
  community_id VARCHAR(36) NOT NULL,
  id CHAR(36) NOT NULL,
  author_id VARCHAR(36) NOT NULL,
  kind ENUM('request','offer','free') NOT NULL,
  title VARCHAR(120) NOT NULL,
  area VARCHAR(80) NOT NULL,
  minutes SMALLINT UNSIGNED,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (community_id, id),
  CHECK ((kind = 'free' AND minutes IS NULL)
      OR (kind <> 'free' AND minutes IS NOT NULL AND minutes BETWEEN 1 AND 1440)),
  FOREIGN KEY (community_id, author_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE services (
  community_id VARCHAR(36) NOT NULL,
  id CHAR(36) NOT NULL,
  post_id CHAR(36) NOT NULL,
  payer_id VARCHAR(36) NOT NULL,
  provider_id VARCHAR(36) NOT NULL,
  minutes SMALLINT UNSIGNED NOT NULL CHECK (minutes BETWEEN 1 AND 1440),
  payer_agreed BOOLEAN NOT NULL DEFAULT FALSE,
  provider_agreed BOOLEAN NOT NULL DEFAULT FALSE,
  payer_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  provider_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  state ENUM('agreement','pending','settled','cancelled','reversed') NOT NULL DEFAULT 'agreement',
  completed_at DATETIME(6),
  PRIMARY KEY (community_id, id),
  UNIQUE (community_id, post_id),
  CHECK (payer_id <> provider_id),
  FOREIGN KEY (community_id, post_id) REFERENCES help_posts(community_id, id),
  FOREIGN KEY (community_id, payer_id) REFERENCES members(community_id, id),
  FOREIGN KEY (community_id, provider_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE time_journals (
  community_id VARCHAR(36) NOT NULL,
  service_id CHAR(36) NOT NULL,
  kind ENUM('settlement','reversal') NOT NULL,
  actor_id VARCHAR(36) NOT NULL,
  reason VARCHAR(500),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (community_id, service_id, kind),
  FOREIGN KEY (community_id, service_id) REFERENCES services(community_id, id),
  FOREIGN KEY (community_id, actor_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE time_entries (
  community_id VARCHAR(36) NOT NULL,
  service_id CHAR(36) NOT NULL,
  kind ENUM('settlement','reversal') NOT NULL,
  member_id VARCHAR(36) NOT NULL,
  delta SMALLINT NOT NULL CHECK (delta <> 0),
  PRIMARY KEY (community_id, service_id, kind, member_id),
  FOREIGN KEY (community_id, service_id, kind)
    REFERENCES time_journals(community_id, service_id, kind),
  FOREIGN KEY (community_id, member_id) REFERENCES members(community_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO lifebuoy_migrations (version, checksum) VALUES ('002_time_bank.sql', '4fb9285a2188937df219c8f6f94b7c2b57159f5e575bba0917b7e6d477a3535a');

-- 003_exchange.sql
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

INSERT INTO lifebuoy_migrations (version, checksum) VALUES ('003_exchange.sql', '669eb46c2501624753b0f98d7455c17001e5ee76caea9d3ed1bd8a20ce3e52d5');

-- 004_ratings.sql
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

INSERT INTO lifebuoy_migrations (version, checksum) VALUES ('004_ratings.sql', 'f6564d052871c0a630385d15e1c7660c8507155d45014c3aeede32a97196012e');

-- 005_member_auth.sql
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

INSERT INTO lifebuoy_migrations (version, checksum) VALUES ('005_member_auth.sql', '2eb3e101bfd646e4eea5fb8fc929b26441c54d5a37b0ac2c32126a5b7a0995ab');
