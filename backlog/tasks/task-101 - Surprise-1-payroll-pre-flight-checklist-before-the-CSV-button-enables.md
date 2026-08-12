---
id: TASK-101
title: 'Surprise 1: payroll pre-flight checklist before the CSV button enables'
status: To Do
assignee: []
created_date: '2026-08-12 06:04'
labels:
  - assistant
  - payroll
dependencies:
  - TASK-100
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design doc §9.1. Closes audit finding 2 — the CSV can carry a number the screen already knows is wrong.

Before the CSV export button becomes enabled on /payroll/, run a fixed five-item checklist over the
SELECTED period and state pass/fail per item:
  1. an open shift inside the period
  2. an unresolved auto_closed shift
  3. a rate change mid-period (decision-30 worker_rates)
  4. a shift over 8 h (decision-10)
  5. a worker who had shifts last month and none this month

The checks are PURE SQL and need no model at all. The model only phrases the summary and TASK-100's
numeral-set verifier guards that phrasing. Serves JTBD-5, the highest-consequence job on the board,
at its single riskiest instant.

Each failing item links to the rows with an ABSOLUTE from/to range. The checklist does not BLOCK the
export — it must be dismissible with 'trotzdem exportieren', because a director who cannot export is
a director who stops using the screen. But the dismissal is recorded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Five checks implemented in SQL; zero model calls needed to compute pass/fail
- [ ] #2 Each failing item links to /shifts/ with from/to absolute; the linked rows reproduce the item
- [ ] #3 Export is not blocked; dismissal is recorded in assistant_audit
- [ ] #4 The summary sentence passes the numeral-set verifier or falls back to the template
- [ ] #5 Runs on the existing /payroll/ period; adds no page-load model call
<!-- AC:END -->
