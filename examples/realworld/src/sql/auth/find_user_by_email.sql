SELECT id, username, email, password_hash, bio, image
FROM users
WHERE email = :email
