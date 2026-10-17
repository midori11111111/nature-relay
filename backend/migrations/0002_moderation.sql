-- Existing demonstration content remains approved; new writes explicitly use pending.
ALTER TABLE users ADD COLUMN public_nickname TEXT NOT NULL DEFAULT 'Nature observer';
ALTER TABLE users ADD COLUMN suspended INTEGER NOT NULL DEFAULT 0 CHECK(suspended IN (0,1));
UPDATE users SET public_nickname = nickname;
ALTER TABLE posts ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'pending'
  CHECK(moderation_status IN ('pending','approved','rejected'));
UPDATE posts SET moderation_status = 'approved';
ALTER TABLE comments ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'pending'
  CHECK(moderation_status IN ('pending','approved','rejected'));
UPDATE comments SET moderation_status = 'approved';
CREATE TABLE blocks (
  blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(blocker_id, blocked_id),
  CHECK(blocker_id != blocked_id)
);
CREATE INDEX blocks_target ON blocks(blocked_id, blocker_id);
CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK(target_type IN ('post','comment','user')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK(reason IN ('inappropriate','harassment','spam','privacy','other')),
  status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved')),
  created_at TEXT NOT NULL,
  UNIQUE(reporter_id,target_type,target_id)
);
CREATE INDEX reports_queue ON reports(status,created_at);
CREATE INDEX posts_moderation ON posts(moderation_status,created_at);
CREATE INDEX comments_moderation ON comments(moderation_status,created_at);
CREATE TRIGGER blocks_capacity BEFORE INSERT ON blocks
WHEN (SELECT COUNT(*) FROM blocks) >= 5000
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
CREATE TRIGGER reports_capacity BEFORE INSERT ON reports
WHEN (SELECT COUNT(*) FROM reports) >= 5000
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
