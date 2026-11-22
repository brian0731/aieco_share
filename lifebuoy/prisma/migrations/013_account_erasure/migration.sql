CREATE TABLE member_chat_identities (
  sender_key CHAR(64) PRIMARY KEY,
  sender_id VARCHAR(64),
  community_id VARCHAR(36),
  member_id VARCHAR(36),
  UNIQUE KEY member_chat_owner (community_id,member_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE member_chat_messages (
  sender_key CHAR(64) NOT NULL,
  message_id CHAR(36) NOT NULL,
  message_key CHAR(64) NOT NULL,
  PRIMARY KEY (sender_key,message_id),
  FOREIGN KEY (sender_key) REFERENCES member_chat_identities(sender_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE removed_chat_messages (
  message_key CHAR(64) PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO removed_chat_messages (message_key)
SELECT DISTINCT target_key FROM content_reports WHERE kind='chat' AND state='removed';

ALTER TABLE content_reports ADD COLUMN chat_sender_key CHAR(64),
  ADD KEY reported_chat_sender (chat_sender_key);

-- Earlier account deletions withdrew listings without erasing their text.
DELETE r FROM content_reports r
  JOIN members m ON (m.community_id,m.id)=(r.reporter_community_id,r.reporter_id)
  WHERE m.account_state='deleted';

DELETE r FROM content_reports r
  JOIN help_posts p ON r.kind='post' AND (p.community_id,p.id)=(r.target_community_id,r.target_id)
  JOIN members m ON (m.community_id,m.id)=(p.community_id,p.author_id)
  WHERE m.account_state='deleted';

DELETE r FROM content_reports r
  JOIN items i ON r.kind='item' AND (i.community_id,i.id)=(r.target_community_id,r.target_id)
  JOIN members m ON (m.community_id,m.id)=(i.community_id,i.owner_id)
  WHERE m.account_state='deleted';

DELETE r FROM ratings r
  JOIN members m ON m.community_id=r.community_id AND m.id IN (r.reviewer_id,r.subject_id)
  WHERE m.account_state='deleted';

DELETE d FROM disputes d JOIN members m ON (m.community_id,m.id)=(d.community_id,d.reporter_id)
  WHERE m.account_state='deleted';

DELETE a FROM audit_log a JOIN members m ON (m.community_id,m.id)=(a.community_id,a.actor_id)
  WHERE m.account_state='deleted';

UPDATE time_journals j JOIN members m ON (m.community_id,m.id)=(j.community_id,j.actor_id)
  SET j.reason=NULL WHERE m.account_state='deleted';

DELETE p FROM help_posts p
  JOIN members m ON (m.community_id,m.id)=(p.community_id,p.author_id)
  LEFT JOIN services s ON (s.community_id,s.post_id)=(p.community_id,p.id)
  WHERE m.account_state='deleted' AND s.id IS NULL;

DELETE i FROM items i
  JOIN members m ON (m.community_id,m.id)=(i.community_id,i.owner_id)
  LEFT JOIN exchanges o ON (o.community_id,o.offered_id)=(i.community_id,i.id)
  LEFT JOIN exchanges w ON (w.community_id,w.wanted_id)=(i.community_id,i.id)
  WHERE m.account_state='deleted' AND o.id IS NULL AND w.id IS NULL;

UPDATE help_posts p JOIN members m ON (m.community_id,m.id)=(p.community_id,p.author_id)
  SET p.title='已刪除的貼文',p.area='',p.withdrawn=TRUE WHERE m.account_state='deleted';

UPDATE items i JOIN members m ON (m.community_id,m.id)=(i.community_id,i.owner_id)
  SET i.title='已刪除的刊登',i.wanted='',i.area='',i.reserved_by=NULL,i.withdrawn=TRUE WHERE m.account_state='deleted';

UPDATE exchanges e
  JOIN members m ON m.community_id=e.community_id AND m.id IN (e.proposer_id,e.owner_id)
  SET e.meeting='' WHERE m.account_state='deleted';
