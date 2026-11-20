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
