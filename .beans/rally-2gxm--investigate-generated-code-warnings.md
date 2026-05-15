---
# rally-2gxm
title: Investigate generated-code warnings
status: todo
type: task
priority: normal
tags:
    - lint
    - codegen
created_at: 2026-05-15T13:34:00Z
updated_at: 2026-05-15T13:36:53Z
---

Glinter warnings in generated code are currently suppressed broadly in gleam.toml, especially label_possible and unnecessary_string_concatenation. Do a proper investigation instead of assuming all warnings are unavoidable.

Questions to answer:
- Which warnings come from Rally source generators versus generated output fixtures/snapshots?
- Which label_possible warnings are on private helpers that can safely use labelled parameters?
- Which warnings are caused by generated code needing stable public/unlabelled APIs?
- Which string-concatenation warnings can be fixed by changing generator source without making generated strings harder to read?
- Are there generated imports or references that can be made cleaner so downstream apps see fewer warnings?

Potential outcome:
- Narrow glinter ignores to only unavoidable generated-code patterns.
- Fix private helper signatures where no public API or generated output contract changes.
- Add focused tests/snapshots so warning fixes do not regress generated code.
- Document any warning classes that are intentionally ignored because generated code requires them.
