---
# lando-6pkm
title: SSR layout with session context
status: todo
type: task
created_at: 2026-05-04T22:51:13Z
updated_at: 2026-05-04T22:51:13Z
---

SSR handler calls layout without ClientContext. Nav bar won't show login state on first server render. Pass pre-populated context based on session cookie.
