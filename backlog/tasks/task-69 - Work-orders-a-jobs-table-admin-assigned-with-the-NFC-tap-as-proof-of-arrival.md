---
id: TASK-69
title: >-
  Work orders: a jobs table, admin-assigned, with the NFC tap as proof of
  arrival
status: To Do
assignee: []
created_date: '2026-08-12 05:45'
labels:
  - design
  - server
  - web
  - ux
  - ios
  - android
milestone: m-6
dependencies: []
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: medium
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. Job dispatch was designed in backlog/docs/JOB-DISPATCH.md and the verdict is: do not build dispatch, build work orders. At 4 workers / 1 location / 8 shifts ever, ranking and pricing are worse than the director's head. A work-order system is useful at N=4 TODAY and is the exact substrate dispatch needs later - the jobs table, the qualification discipline and the tap-as-arrival link are unchanged when ranking arrives on top.

SHAPE - JOB-DISPATCH.md sections 1 and 9. IN scope:
  * jobs table, fields per 1.1, every REQUIRED field NOT NULL. Money integer cents, time
    integer minutes, Europe/Vienna. location_id is a UUID (decision-21), never a slug.
  * states per 1.3: draft -> qualified -> assigned -> accepted -> started -> done -> verified,
    plus cancelled / rejected / failed / blocked_materials. Transitions as an EXPLICIT
    transition table in routes/, never a free status assignment from a client - copy the
    pattern material_requests already uses in routes/admin.js.
  * admin creates a job and assigns it to ONE NAMED WORKER. Human picks. No scoring.
  * worker screen: 'meine Auftraege heute'. Accept, or decline with a reason.
  * the EXISTING NFC tap flips accepted -> started. No arrival button. A self-declared
    arrival is a claim; a tap at the door is evidence, and it already ships.
  * access_note - how the worker physically gets in. Largest single cause of a wasted trip.
  * one admin list: today's jobs, coloured by state.

OUT of scope, deliberately (JOB-DISPATCH.md section 10): pricing, ranking, offer waves,
escalation timers, presence/online state, reliability scores, per-worker stock, the health
screen. Each has a named scale gate; none is met.

CONSTRAINTS. Server deps stay pg + @sentry/node (decision-23). Web adds no npm dependency.
de.json/en.json exact key parity, no bare JSX literals. Tables become labelled cards below
768px via .data-table + ResponsiveTableLabels (decision-29). Migration is ADDITIVE ONLY and
NULLable/DEFAULTed, per the 005 header.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 jobs table exists as an additive migration; every field marked REQUIRED in JOB-DISPATCH.md 1.1 is NOT NULL, and a job cannot leave draft with any of them unset
- [ ] #2 status transitions are an explicit transition table in server/routes/, mutation-tested: an illegal transition (e.g. draft -> started) is REJECTED and the test proves it goes RED if the table is removed
- [ ] #3 admin can create a job, qualify it against the section 1.2 checklist, and assign it to one named worker; there is no auto-assignment code path
- [ ] #4 worker app (iOS + Android) lists today's assigned jobs and can accept or decline-with-reason
- [ ] #5 an NFC tap at the job's location flips that worker's accepted job to started; proven on physical hardware, not a simulator
- [ ] #6 access_note is captured and shown to the worker before they accept
- [ ] #7 de.json and en.json keep exact key parity; pnpm check passes; no bare JSX literals
- [ ] #8 the admin job list renders as labelled cards below 768px (decision-29)
<!-- AC:END -->
