---
id: TASK-109
title: >-
  The five domain states get one vocabulary: word, then texture, then tint - and
  never a silent 0,00 EUR
status: To Do
assignee: []
created_date: '2026-08-12 06:10'
labels:
  - ux
  - web
  - i18n
  - design
milestone: m-6
dependencies:
  - TASK-106
  - TASK-104
documentation:
  - backlog/docs/DESIGN-SYSTEM.md
modified_files:
  - web/messages/de.json
  - web/messages/en.json
priority: medium
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DESIGN-SYSTEM sections 4, 6.5 and 6.6.

JOB: JTBD #1 - the exception scan. The director is looking for the rows that are not normal, and
today "not normal" is spelled five different ways across three screens.

THE FIVE STATES, one rendering rule each, colour is signal number three:
  open                       laufend
  auto-closed-unresolved     automatisch beendet, ungeklaert   <- the one that costs money
  corrected                  geaendert - MUST print the old value, not just the new one
  inactive                   inaktiv
  excluded-from-payroll      renders an em dash. NEVER a silent 0,00 EUR.

The em dash rule is the load-bearing one: a zero is a claim that the work was worth nothing;
an em dash is a claim that this row does not belong in this column. They are different facts and
the payroll CSV carries whichever one the screen chose.

Also in scope: .notice/.callout severities (DESIGN-SYSTEM 6.6) so TASK-104 has a correct place to
put its caveats.

MUST NOT REGRESS: decision-10 (8h auto-timeout with mandatory resolution) semantics; decision-30
audit trail on money edits - the old value shown must come from the audit trail once TASK-55 lands,
and until then from whatever the correction record already holds.

SEQUENTIAL with TASK-104 and TASK-114: all three edit web/messages/de.json and en.json.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One shared component renders all five states; grep proves no screen hand-rolls a sixth spelling
- [ ] #2 A check asserts an excluded-from-payroll cell renders the em dash and never the string 0,00; changing it to render zero -> RED
- [ ] #3 A corrected row prints the previous value alongside the current one
- [ ] #4 Each state is distinguishable without colour: assert the accessible name contains the word, on all five
- [ ] #5 de/en key parity exact; no bare JSX literal
<!-- AC:END -->
