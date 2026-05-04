UPDATE users
SET image = :image, username = :username, bio = :bio, email = :email, updated_at = :now
WHERE id = :user_id
