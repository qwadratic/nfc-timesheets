---
id: TASK-108
title: '.disclosure: the create forms fold away and sit below the list they interrupt'
status: To Do
assignee: []
created_date: '2026-08-12 06:10'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - web
milestone: m-5
dependencies:
  - TASK-106
documentation:
  - backlog/docs/UX-AUDIT.md
  - backlog/docs/DESIGN-SYSTEM.md
priority: medium
ordinal: 1800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 9. DESIGN-SYSTEM 6.7.

JOB: JTBD #1 and #2 - the morning exception scan and closing a stuck shift. Both are read jobs on a
phone, and both currently begin with five swipes past a form.

MEASURED: /shifts/ - the Schichtprotokoll starts 1030px down at 1280px and ~1900px down at 390px,
under a filter bar, a four-field manual-entry form and a correction section
(shifts-populated-390.png). Same inversion on /workers/ (form ends 730px), /locations/ (830px),
/inventory/, /clients/. The form is always expanded, never a disclosure.

These screens are documented as verification screens - shifts.intro literally says "diese Liste
daher vor jeder Lohnabrechnung pruefen" - and laid out as data-entry screens.

FIX: native <details>/<summary> styled as .disclosure. No JS state, no library, no new dependency.
List first, form after it, collapsed by default. Deep-link an open form with the section anchor;
the parameter contract (TASK-113) says a param may open a panel and must never apply one.

MUST NOT REGRESS: keyboard operability (details/summary is free); the form still submits;
44px targets at 390px; German labels.

PARALLEL: yes with the server and ops tasks. NOT with TASK-107 or TASK-110 - same page-level TSX.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The five create forms (/shifts/, /workers/, /locations/, /inventory/, /clients/) are collapsed by default and rendered after the list
- [ ] #2 A check asserts the first data row of each list appears above the create form in DOM order on all five screens; swapping one back -> RED
- [ ] #3 Measured: the first shift row is visible above the fold at 390px (< 900px from the top). Frame in docs/media/states/ proves it
- [ ] #4 Opening the disclosure is possible by keyboard alone and the summary is a >= 44px target at 390px
<!-- AC:END -->
