---
# rally-q304
title: Update SSR wire encoding
status: todo
type: task
priority: normal
tags:
    - wire
    - ssr
created_at: 2026-05-09T13:53:07Z
updated_at: 2026-05-09T13:53:07Z
---

Validation:
- This belongs in Rally, not Libero.
- `src/rally/generator/ssr_handler.gleam` still emits per-type `wire_encode_*` wrappers for client context and page flags when a wire module is configured.
- `src/rally.gleam` still passes `option.Some(config.wire_module)` to `libero.generate_dispatch` and to `ssr_handler.generate`.
- Page model seeds still look needed for generated JS decoders and `__wireAtom` metadata, so do not remove them without checking codec generation.

Dependency:
- Wait for Libero bean `libero-6vj3` to remove dispatch wire transform wrappers and settle the new Libero API.

Work:
- Update Rally to the new Libero dispatch API.
- Remove SSR-specific wire wrapper generation if `codec.encode_flags` can rely on the centralized `wire.encode` path.
- Keep page model seed discovery if JS decoder generation still needs it.

Acceptance:
- Rally builds against the updated Libero API.
- SSR flags and client context still encode with hashed wire atoms.
- Rally tests pass, then smoke test a route that renders SSR flags.
