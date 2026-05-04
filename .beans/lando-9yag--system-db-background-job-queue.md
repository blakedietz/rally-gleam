---
# lando-9yag
title: 'System DB: background job queue'
status: todo
type: task
created_at: 2026-05-04T23:11:35Z
updated_at: 2026-05-04T23:11:35Z
---

Add jobs table to system.db. Public API: system.enqueue(name, payload, run_at), system.enqueue_in(name, payload, delay_seconds). Job runner process spawned at app startup, polls jobs table, calls user-defined handler callback. Retry with backoff, dead letter on max attempts.
