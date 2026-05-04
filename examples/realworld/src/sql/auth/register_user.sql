INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
VALUES (:username, :email, :password_hash, :bio, :image, :created_at, :updated_at)
RETURNING id, username, email, bio, image
