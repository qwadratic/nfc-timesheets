---
id: TASK-117
title: '/pl/ and /analytics/ become /reports/ - one labour computation, not two'
status: To Do
assignee: []
created_date: '2026-08-12 06:12'
labels:
  - ux
  - web
  - reporting
  - money
milestone: m-6
dependencies:
  - TASK-105
  - TASK-115
documentation:
  - backlog/docs/IA-AND-JTBD.md
  - backlog/docs/UX-AUDIT.md
priority: medium
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 2. The merge that is not cosmetic.

Both screens take the same two dimensions (building x period) and both compute labour. TWO SCREENS
COMPUTING THE SAME MONEY IS HOW UX-AUDIT FINDING 6 HAPPENED (1.091,25 vs 1.211,25 on one page).
The merge removes the second implementation; TASK-105 fixes the arithmetic first so the survivor is
the correct one.

    /reports/?report=pl     Gewinn und Verlust
    /reports/?report=time   Zeit und Auslastung

Money links into this screen MUST carry absolute from/to, never a named period (parameter contract,
TASK-113): a named period re-resolves tomorrow and stops reproducing the number being defended.

Server side stays as it is: GET /admin/pl and GET /admin/analytics remain two calls behind one
screen. No endpoint changes - stated explicitly so nobody assumes otherwise.

JOB: JTBD #7 and #8.

MUST NOT REGRESS: decision-6 pro-rata materials; decision-10 exclusions; decision-28 contract
history; the CSV exports from both screens.

SEQUENTIAL after TASK-105 and TASK-115. Not in parallel with TASK-116.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One labour computation remains; grep proves the second implementation is deleted, not merely unused
- [ ] #2 V8: a /payroll/ row links to /shifts/?from&to, and summing those durations reproduces the payroll cell exactly. Swapping the link to period=lastMonth and running it on the 1st of a month -> RED
- [ ] #3 Both old routes redirect with query preserved and map to the right ?report= value
- [ ] #4 No server endpoint changed - asserted by diffing the route table
- [ ] #5 The TASK-105 sum check still passes on the merged screen
<!-- AC:END -->
