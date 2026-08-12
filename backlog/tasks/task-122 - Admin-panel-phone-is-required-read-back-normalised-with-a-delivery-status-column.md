---
id: TASK-122
title: >-
  Admin panel: phone is required, read back normalised, with a delivery status
  column
status: To Do
assignee: []
created_date: '2026-08-12 06:13'
labels:
  - ux
  - web
  - i18n
milestone: m-6
dependencies:
  - TASK-121
documentation:
  - backlog/docs/SMS-AUTH.md
priority: medium
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH section 9, implementation step 3.

The admin types a number, the server normalises it, and THE SCREEN SHOWS WHAT WAS STORED - not what
was typed. A normaliser whose result is invisible is a normaliser nobody trusts.

Also: a status column (kann SMS empfangen / bestaetigt / nicht bestaetigt), and revoke-on-change -
changing a workers number kills that workers sessions, visibly, with the consequence stated before
the confirm.

JOB: JTBD #3 - invite a worker on the spot, standing in a stairwell, on a phone.

MUST NOT REGRESS: decision-29 - this must work at 390px as labelled cards, not a table.
de/en key parity. No bare JSX literal. 44px targets.

PARALLEL with the server work; SEQUENTIAL after TASK-121. Touches web/messages/*.json -
serialise against TASK-104/109/110/114.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Saving a number renders the normalised E.164 back, not the typed string - asserted for 0664..., +43..., 0043...
- [ ] #2 The worker row shows a phone status derived from columns, never from a guess: has a number / confirmed / can receive SMS
- [ ] #3 Changing a number revokes that workers sessions, and the dialog says so BEFORE the confirm, in German
- [ ] #4 Renders as labelled cards at 390px per decision-29; frame in docs/media/states/
- [ ] #5 de/en parity exact
<!-- AC:END -->
