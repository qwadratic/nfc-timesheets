---
id: TASK-118
title: 'Twenty context-carrying cross-links, and every money link is absolute'
status: To Do
assignee: []
created_date: '2026-08-12 06:12'
labels:
  - ux
  - web
milestone: m-6
dependencies:
  - TASK-113
documentation:
  - backlog/docs/IA-AND-JTBD.md
priority: low
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 3.2 and 3.3 - the cross-link map and its German labels.

The point is one sentence from the doc: an insight you cannot click through to the rows is a rumour.
Every aggregate on every screen gets a link to the rows that produced it, carrying its context in
absolute from/to.

JOB: JTBD #4, #5, #7 - every job that ends with "prove it".

MUST NOT REGRESS: TASK-113s G1 (a link opens a view, never performs an action) and the rule that
/payroll/?worker= highlights and never filters.

PARALLEL: yes, after TASK-113 and the merges have settled. Lowest priority in the IA group - it is
the polish that only pays once the screens have stopped moving.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The twenty links in section 3.3 exist with their documented German labels
- [ ] #2 Every link that carries money context uses absolute from/to; a check greps for period= on money links and fails on any
- [ ] #3 Following any of the twenty reproduces the source number - spot-checked on three, documented as arithmetic in the notes
<!-- AC:END -->
