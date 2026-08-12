---
id: TASK-104
title: >-
  Payroll caveat lies about the sign, hides the row cap, and the CSV carries
  neither
status: To Do
assignee: []
created_date: '2026-08-12 06:08'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - web
  - payroll
  - money
milestone: m-5
dependencies: []
references:
  - backlog/docs/UX-AUDIT.md
documentation:
  - backlog/docs/UX-AUDIT.md
modified_files:
  - web/lib/payroll.ts
  - web/app/payroll/page.tsx
  - web/messages/de.json
  - web/messages/en.json
priority: high
ordinal: 1100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 2. The highest money risk on the board.

JOB it serves: JTBD #5 - month-end pay. Rarest job, worst consequence: the CSV is what the
accountant pays from.

WHAT IS WRONG (all in one screenshot, docs/media/states/payroll-overlimit-reconcile-1280.png):
  server aggregate 1.093,25 EUR  vs  rows on screen 121.334,00 EUR
  1. payroll.caveatReconcile ends "Diese Summe ist daher zu niedrig." unconditionally.
     web/lib/payroll.ts:180 returns missingCents = serverCents - visibleCents and the sign is
     never read, so an over-count is announced as an under-count.
  2. caveatTruncated - the only string that names the 2000-row cap - is suppressed whenever the
     truncated tail still reaches past the period start (web/app/payroll/page.tsx:315,
     web/lib/payroll.ts:161).
  3. The Gesamt row is bold and unmarked and "CSV herunterladen" stays enabled
     (web/app/payroll/page.tsx:440). downloadCsv writes headers + lines + total and no caveat,
     no truncation flag, no reconciliation line (web/app/payroll/page.tsx:182-200).

SHAPE OF THE FIX:
  - three message keys, not one: zu niedrig / zu hoch / genau. Choose on Math.sign(missingCents).
  - the cap notice is a property of "the query hit 2000 rows", not of period coverage.
  - the CSV gets a leading caveat row when any caveat is live, in the same words the screen uses.
  - money stays integer cents end to end. Never format then subtract.

MUST NOT REGRESS: de.json/en.json key parity (814/814 today); no bare JSX literal;
the existing Gesamt number when there is no truncation and no reconciliation gap.

PARALLEL: yes with everything except TASK-109 and TASK-114 - all three touch web/messages/*.json,
which cannot survive concurrent editors. Serialise those three.

Production is READ-ONLY. Reproduce against nfc_demo.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A reconciliation gap in EITHER direction prints the correct direction; a fixture with visibleCents > serverCents renders "zu hoch" and never "zu niedrig"
- [ ] #2 The 2000-row cap notice renders whenever the row cap was hit, independent of whether the tail reaches past the period start
- [ ] #3 downloadCsv emits every live caveat as a leading row; a fixture with a reconciliation gap produces a CSV whose first data line names it
- [ ] #4 Mutation proof recorded: revert the sign check -> the "zu hoch" assertion goes RED; revert the CSV caveat -> the CSV assertion goes RED. Paste both RED outputs into the notes
- [ ] #5 de.json/en.json key parity stays exactly equal; pnpm check green
- [ ] #6 Evidence: a demo frame of the over-count case showing the correct direction, plus the CSV text for that same fixture
<!-- AC:END -->
