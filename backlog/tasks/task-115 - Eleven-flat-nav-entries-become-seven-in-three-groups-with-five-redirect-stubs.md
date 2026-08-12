---
id: TASK-115
title: 'Eleven flat nav entries become seven in three groups, with five redirect stubs'
status: To Do
assignee: []
created_date: '2026-08-12 06:11'
labels:
  - ux
  - web
milestone: m-6
dependencies: []
documentation:
  - backlog/docs/IA-AND-JTBD.md
modified_files:
  - web/lib/nav.ts
priority: medium
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 2. The nav-only half of the route consolidation - deliberately split from the
screen merges so the risky part is separate from the cheap part.

    HEUTE        /  .  /shifts/  .  /material-requests/
    GELD         /payroll/  .  /reports/
    STAMMDATEN   /workers/  .  /locations/

The grouping comes from the JTBD ranking: the top four jobs are all FIELD jobs, all on a phone, and
all live in HEUTE. /clients/ and /inventory/ are not jobs at all - nobody opens the panel to do them
- which is why they become tabs (TASK-116) rather than entries.

Five bookmark-preserving redirect stubs, QUERY STRING PRESERVED: /clients/, /contracts/,
/inventory/, /pl/, /analytics/.

JOB: all of them, weakly. This is the cheapest change in the IA doc and the one that makes the
others legible.

MUST NOT REGRESS: decision-29 - the nav works on a phone; keyboard order; the skip link;
every existing bookmark resolves.

SEQUENTIAL AND ALONE: web/lib/nav.ts cannot survive concurrent editors. TASK-116 and TASK-117
depend on this landing first. This task adds the GROUPS and the STUBS; it does not move a screen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 web/lib/nav.ts renders seven entries in three named German groups; the group headings are real markup, not visual grouping only
- [ ] #2 V10: all five old routes still resolve from a bookmark with the query string preserved. Deleting out/pl/index.html -> RED
- [ ] #3 Keyboard traversal reaches every entry in visual order; the skip link still lands on main
- [ ] #4 Evidence: 1280px and 390px frames of the new nav
<!-- AC:END -->
