---
id: TASK-105
title: P&L Gesamt labour does not equal the sum of its own column
status: To Do
assignee: []
created_date: '2026-08-12 06:08'
updated_date: '2026-08-12 06:14'
labels:
  - web
  - reporting
  - money
milestone: m-5
dependencies: []
documentation:
  - backlog/docs/UX-AUDIT.md
modified_files:
  - web/lib/pl.ts
priority: high
ordinal: 1200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 6. Two numbers on one screen, both labelled labour, differing by 120,00 EUR
(1.091,25 vs 1.211,25). web/lib/pl.ts:147.

JOB: JTBD #7 - is this building making money. A total that does not add up destroys the screen,
because the director cannot tell which of the two numbers to defend.

ROOT CAUSE is structural and named in IA-AND-JTBD section 2: /pl/ and /analytics/ compute the same
labour figure twice. This task fixes the arithmetic where it is; TASK-117 removes the second
computation by merging the screens. Do the arithmetic first - a merge that carries a wrong number
forward is worse than two honest screens.

FIX: the Gesamt row must be the sum of the rendered column, or the column must be the decomposition
of the Gesamt. Pick one direction and make the other derive from it. Integer cents throughout;
round once, at the end, never per row and then again on the total.

MUST NOT REGRESS: decision-6 pro-rata material attribution; decision-28 (labour valued at current
rates until worker_rates exists); the revenue side of the same table.

PARALLEL: yes. Touches web/lib/pl.ts only - no shared file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A runnable check asserts sum(column) === Gesamt for at least three fixtures including one with an excluded (auto-closed, unresolved) shift and one with a zero-hour worker
- [ ] #2 The check is shown RED against todays lib/pl.ts before the fix, and the RED output is pasted into the notes
- [ ] #3 The number the screen shows is reproducible by hand from the rows it shows - documented as one line of arithmetic in the task notes
- [ ] #4 Excluded shifts are visibly excluded, never silently dropped: an excluded row renders an em dash, never 0,00 EUR
<!-- AC:END -->
