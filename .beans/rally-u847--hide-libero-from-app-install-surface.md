---
# rally-u847
title: Hide Libero from app install surface
status: todo
type: task
priority: normal
tags:
    - docs
    - codegen
created_at: 2026-05-14T00:58:43Z
updated_at: 2026-05-14T00:58:43Z
---

Generated Rally apps currently import libero modules directly, so users must add libero as an app dependency. Make generated code import Rally-owned facades instead so onboarding can be just `gleam add rally`.
