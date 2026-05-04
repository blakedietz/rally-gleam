UPDATE users
SET image = :image, username = :username, bio = :bio, email = :email,
    password_hash = :password_hash, updated_at = :now
WHERE id = :user_id
