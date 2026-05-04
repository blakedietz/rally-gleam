SELECT a.id, a.slug, a.title, a.description, a.body, a.created_at, a.author_id,
       u.username, u.image, u.bio
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE a.slug = :slug
