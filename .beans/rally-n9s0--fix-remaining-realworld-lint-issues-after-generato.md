---
# rally-n9s0
title: Fix remaining realworld lint issues after generator cleanup
status: todo
type: task
priority: high
created_at: 2026-05-09T13:52:32Z
updated_at: 2026-05-09T13:52:32Z
---

Context: After fixing 39 mechanical lint issues, 166 remain in realworld user code. Most need coordinated fixes in generators first.

Breakdown:
- 68 label_possible: Generator function params need labels first, then user code call sites updated
- 37 assert_ok_pattern: Intentional patterns; need architectural decision on error handling
- 30 unused_exports: False positives from generated/ exclusion; resolve when generated code is linted
- 17 thrown_away_error: Need result combinator refactoring
- 15 deep_nesting: Extract helper functions

Approach: Fix generator output to be lint-clean first, then update realworld user code to match. RealWorld is the only Rally consumer.
