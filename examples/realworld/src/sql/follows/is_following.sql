SELECT COUNT(*) as count FROM follows WHERE follower_id = :follower_id AND followed_id = :followed_id
