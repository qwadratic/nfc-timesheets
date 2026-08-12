---
id: TASK-114
title: 'Every screen answers one German question, rendered as the subhead'
status: To Do
assignee: []
created_date: '2026-08-12 06:11'
labels:
  - ux
  - i18n
  - web
milestone: m-6
dependencies: []
documentation:
  - backlog/docs/IA-AND-JTBD.md
modified_files:
  - web/messages/de.json
  - web/messages/en.json
priority: medium
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 4, the "clear answer" rule.

Each screen states, under its h1, the one question it answers. Not documentation - rendered text.
The rule that did the work during the IA pass: four screens could not state a question, and those
four are exactly the ones that got merged (TASK-116, TASK-117). The test has already paid for
itself once; rendering it keeps it paying.

Examples: /shifts/ -> "Welche Schichten muessen vor der Abrechnung geklaert werden?"
          /payroll/ -> "Was ist in diesem Zeitraum an wen zu zahlen?"

JOB: every job. A director who lands on a screen from a bookmark and cannot tell what it is for is
the same director who calls instead of reading.

MUST NOT REGRESS: heading structure (h1 then subhead, not two h1s); screen-reader order;
de/en key parity.

SEQUENTIAL with TASK-104 and TASK-109 - shared messages files. Cheap; slot it whenever the messages
files are free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V1: a check asserts every routes h1 is followed by its question string; deleting one question key fails both the parity check and the assertion
- [ ] #2 The question is a subhead, not a second h1 - heading level check passes
- [ ] #3 Both locales carry all question keys; parity exact
- [ ] #4 Screens added after this task inherit the check by construction: the check enumerates routes, it does not hold a hand-written list
<!-- AC:END -->
