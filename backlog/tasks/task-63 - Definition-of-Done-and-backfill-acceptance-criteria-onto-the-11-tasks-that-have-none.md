---
id: TASK-63
title: >-
  Definition of Done, and backfill acceptance criteria onto the 11 tasks that
  have none
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-5
dependencies: []
priority: medium
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
No Definition of Done string exists in backlog/, AGENTS.md or README.md. 11 of 53 tasks carry ZERO acceptance criteria - and they are almost entirely the NEWEST ones: task-45,46,47,48,49,50,51,52,53 plus 30 and 31. Every task from task-45 onward has none.

The trend is the wrong way: the tasks written since the customer started using the system are the ones with no completion test. Compare task-41, which has six sharp falsifiable criteria including On a PHYSICAL phone: tag tap to shift logged, with the app fully closed. That is exemplary and it is the older document.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 backlog/docs/DEFINITION-OF-DONE.md, specific to this stack: all check suites pass, no decision violated, German+English key parity (web/scripts/check.mjs rule 2), deployed AND verified on the live host, CHANGELOG entry, and for anything touching the tap path proven on physical hardware
- [ ] #2 AC backfilled onto all 11 tasks that currently have none
- [ ] #3 Every task carries an effort field (S under 2h / M half a day / L multi-day, split it) sized in AGENT hours - no task currently has any sizing, which is why the pilot milestone cannot be dated
<!-- AC:END -->
