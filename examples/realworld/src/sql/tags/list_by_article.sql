SELECT t.name
FROM tags t
JOIN article_tags at ON t.id = at.tag_id
WHERE at.article_id = :article_id
