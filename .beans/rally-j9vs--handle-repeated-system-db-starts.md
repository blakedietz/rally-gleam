---
# rally-j9vs
title: Handle repeated system DB starts
status: todo
type: task
priority: deferred
tags:
    - runtime
created_at: 2026-05-14T22:58:47Z
updated_at: 2026-05-14T22:58:47Z
---

system.open_and_store opens a fresh SQLite connection and writes global state on every start. That preserves existing behavior, but supervised job-runner restarts make repeated starts more likely. Replace or close old global state deliberately in a future pass.
