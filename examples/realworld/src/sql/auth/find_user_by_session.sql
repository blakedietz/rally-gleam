SELECT u.id, u.username, u.email, u.bio, u.image
FROM users u
JOIN sessions s ON u.id = s.user_id
WHERE s.session_id = :session_id
