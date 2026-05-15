---
# rally-qmij
title: Consolidate Rally runtime namespace
status: todo
type: task
priority: deferred
tags:
    - cleanup
    - v2
    - api
created_at: 2026-05-15T13:25:09Z
updated_at: 2026-05-15T13:25:56Z
---

Rally currently exposes modules in two top-level Gleam namespaces: rally/* and rally_runtime/*. The rally_ prefix on FFI modules lowers collision risk, but the public Gleam namespace split is still discouraged.\n\nPotential fix for v2:\n- Move public runtime modules from src/rally_runtime/*.gleam to src/rally/runtime/*.gleam.\n- Move runtime internals from src/rally_runtime/internal/*.gleam to src/rally/runtime/internal/*.gleam.\n- Update generated code, scaffold files, README examples, docs, tests, and fixtures to import rally/runtime/... instead of rally_runtime/....\n- Keep Erlang/JS FFI module names prefixed with rally_ where needed to avoid BEAM/global JS collisions.\n- If feasible, keep rally_runtime/* wrapper modules for one release that re-export or delegate to rally/runtime/*, then remove them in the next major.\n- Add a smoke test that scans generated client and scaffold imports so new public examples do not reintroduce rally_runtime/*.\n\nThis is an API migration because README examples, generated code, and user apps currently import rally_runtime directly.
