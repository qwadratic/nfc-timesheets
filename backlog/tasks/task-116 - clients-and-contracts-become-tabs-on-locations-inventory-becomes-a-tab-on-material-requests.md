---
id: TASK-116
title: >-
  /clients/ and /contracts/ become tabs on /locations/; /inventory/ becomes a
  tab on /material-requests/
status: To Do
assignee: []
created_date: '2026-08-12 06:11'
labels:
  - ux
  - web
milestone: m-6
dependencies:
  - TASK-115
documentation:
  - backlog/docs/IA-AND-JTBD.md
priority: medium
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 2, the two low-risk merges.

WHY: both a client and a contract are properties of a BUILDING. /contracts/ already forces the
director to pick a building before it can show anything - that is a tab wearing a route costume.
And the material-request queue is the catalogues only consumer, so a catalogue that is its own
route is a route nobody navigates to on purpose.

The merge is what stops four screens existing that could not state the one question they answer
(TASK-114s test).

JOB: JTBD #6 (materials), #9 and #12 (who is this building for, what did we agree).

MUST NOT REGRESS: every form that lives on the merged screens still submits; the contract history
view (decision-28) keeps working; deep links to a specific client or contract still land on it -
via ?tab= per the parameter contract, which OPENS and never APPLIES (G1).

SEQUENTIAL after TASK-115. Do not run in parallel with TASK-117 - both restructure route files and
both touch the nav.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The four merged screens are reachable as tabs and the old routes redirect with query preserved
- [ ] #2 A tab is selected by a URL param, is keyboard operable, and announces its selected state
- [ ] #3 No form lost: a check enumerates the form actions present before and after and asserts the set is unchanged
- [ ] #4 Each surviving screen can state its one question (TASK-114) - that is the acceptance test for whether the merge was right
<!-- AC:END -->
