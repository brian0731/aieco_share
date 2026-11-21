ALTER TABLE members
  ADD COLUMN origin_community_id VARCHAR(36) NULL,
  ADD COLUMN account_state ENUM('active','moved','deleted') NOT NULL DEFAULT 'active',
  ADD KEY members_account_history (id, origin_community_id),
  ADD CONSTRAINT members_origin_fk FOREIGN KEY (origin_community_id, id) REFERENCES members(community_id, id);

ALTER TABLE help_posts ADD COLUMN withdrawn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN withdrawn BOOLEAN NOT NULL DEFAULT FALSE;
