---
id: TASK-113
title: >-
  URL parameter contract: a param is a view and never an action, and an unknown
  id shows everything
status: To Do
assignee: []
created_date: '2026-08-12 06:11'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - web
milestone: m-6
dependencies:
  - TASK-107
documentation:
  - backlog/docs/IA-AND-JTBD.md
priority: medium
ordinal: 1900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IA-AND-JTBD section 5 - nine global rules and the per-screen contract. New file web/lib/params.ts.

THE TWO LOAD-BEARING RULES:
  G1  a param is a VIEW, never an ACTION.  ?panel=rate opens a panel; it never applies a rate.
  G4  a valid-looking id for an entity that does not exist -> show ALL rows plus a banner
      ("es fehlt nichts"). NEVER an empty table. An empty table here is audit finding 8 wearing
      a URL: it tells the director there is no work when in fact there is no such filter target.

ALSO BINDING:
  - from/to (absolute ISO) beat period (named) on every MONEY link. A named period re-resolves
    tomorrow and stops reproducing the number the director is defending in a meeting.
  - /payroll/?worker= HIGHLIGHTS, it never filters. A filtered payroll has a lying Gesamt, and
    Gesamt is exactly what the CSV carries (see TASK-104).
  - /login/?next= only accepts a same-origin path.

JOB: JTBD #4, #5, #7 - every job where the director has to defend a number to someone else.

MUST NOT REGRESS: existing bookmarks; TASK-107s Load<T> states - an unknown id is READY plus a
banner, not an error and not an empty.

SEQUENTIAL after TASK-107. PARALLEL with TASK-115/116/117 only if those land first - all four touch
routing-adjacent page code; prefer to run this AFTER the nav regroup so params are written once
against the final route set.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 web/lib/params.ts parses and validates every documented param; unknown values fall back to the documented default rather than throwing
- [ ] #2 V4: ?worker=999999 shows ALL rows plus the banner. Making the filter drop unknown ids silently -> row count 0 -> RED
- [ ] #3 V5: every documented URL replayed against nfc_demo changes zero rows - diff row counts before and after. Adding a ?panel=rate&apply=1 shortcut -> RED
- [ ] #4 V6: /login/?next=https://evil.example/ lands on /. Accepting any next value -> RED
- [ ] #5 V7: /payroll/?worker=<id> leaves Gesamt unchanged. Making it filter -> RED
- [ ] #6 Production is READ-ONLY: the replay runs against nfc_demo, guarded by demo/check-guards.sh
<!-- AC:END -->
