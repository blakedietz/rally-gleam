INSERT OR REPLACE INTO sessions (session_id, user_id, created_at, expires_at)
VALUES (:session_id, :user_id, :now, :expires_at)
