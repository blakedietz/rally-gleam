---
# lando-8tkl
title: Client-side send_to_client_context
status: todo
type: task
created_at: 2026-05-04T16:05:59Z
updated_at: 2026-05-04T16:05:59Z
---

send_to_client_context is a server-side no-op. On JS target, it should dispatch ClientContextUpdate messages through Lustre so pages can update shared state (e.g. SignedIn after login).
