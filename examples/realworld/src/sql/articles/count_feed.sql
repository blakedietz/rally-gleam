SELECT COUNT(*) as count
FROM articles a
WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id)
