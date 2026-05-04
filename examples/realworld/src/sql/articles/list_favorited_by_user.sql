SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
FROM articles a
JOIN users u ON a.author_id = u.id
JOIN favorites f ON f.article_id = a.id
WHERE f.user_id = :user_id
ORDER BY a.created_at DESC
LIMIT 20
