PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  nickname TEXT NOT NULL CHECK(length(nickname) BETWEEN 1 AND 40),
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE TABLE posts (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_observation_id TEXT NOT NULL,
  payload TEXT NOT NULL CHECK(json_valid(payload)),
  photo_base64 TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(author_id, client_observation_id)
);
CREATE INDEX posts_created ON posts(created_at DESC, id DESC);
CREATE INDEX posts_author_created ON posts(author_id, created_at DESC);
CREATE TABLE comments (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text TEXT NOT NULL CHECK(length(text) BETWEEN 1 AND 1000),
  created_at TEXT NOT NULL
);
CREATE INDEX comments_post_created ON comments(post_id, created_at, id);
CREATE INDEX comments_author ON comments(author_id);
CREATE TABLE follows (
  follower_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(follower_id, following_id),
  CHECK(follower_id != following_id)
);
CREATE TABLE request_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX request_limits_expiry ON request_limits(expires_at);

-- Atomic capacity checks keep this small public demo below free database storage limits.
CREATE TRIGGER users_capacity BEFORE INSERT ON users WHEN (SELECT COUNT(*) FROM users) >= 500
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
CREATE TRIGGER posts_capacity BEFORE INSERT ON posts
WHEN (SELECT COUNT(*) FROM posts) >= 1000 OR (SELECT COUNT(*) FROM posts WHERE author_id=NEW.author_id) >= 50
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
CREATE TRIGGER comments_capacity BEFORE INSERT ON comments
WHEN (SELECT COUNT(*) FROM comments) >= 5000 OR (SELECT COUNT(*) FROM comments WHERE post_id=NEW.post_id) >= 100
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
CREATE TRIGGER follows_capacity BEFORE INSERT ON follows WHEN (SELECT COUNT(*) FROM follows) >= 5000
BEGIN SELECT RAISE(ABORT, 'demo_capacity'); END;
