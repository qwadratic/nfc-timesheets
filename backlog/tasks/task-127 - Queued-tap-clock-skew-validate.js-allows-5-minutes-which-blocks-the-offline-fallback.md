---
id: TASK-127
title: >-
  Queued-tap clock skew: validate.js allows 5 minutes, which blocks the offline
  fallback
status: To Do
assignee: []
created_date: '2026-08-12 06:14'
labels:
  - server
milestone: m-6
dependencies: []
documentation:
  - backlog/docs/SMS-AUTH.md
priority: low
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH open item 2, named rather than hidden.

The delivery-failure ladder (section 7) has "the tap queues locally" as its fourth rung. It does not
work today: server/lib/validate.js accepts a client timestamp only within 5 minutes of now, so a tap
queued in a basement and flushed twenty minutes later is rejected.

WHY THIS IS NOT A ONE-LINE FIX: start_time is a MONEY-PRODUCING FIELD. Widening the window widens
how far a client can move a payslip. That is a policy change, not a constant change, and it needs
its own decision record naming the new bound and what compensates for it (server-side receipt time
stored alongside, an audit flag on skewed rows, a cap on the skew that can pass silently).

Do NOT widen the constant as part of any other task. Write the decision first.

JOB: JTBD #11 - did the tap land, in a building with no signal.

MUST NOT REGRESS: decision-19 - the shift is posted at clock-IN and the server is authoritative for
open shifts. decision-30 - every money edit leaves an audit trail; a skew-accepted row is exactly
the kind of thing that trail is for.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision record exists naming the new bound, what is recorded alongside a skewed timestamp, and what a director sees for such a row
- [ ] #2 The current 5-minute rejection is reproduced as a check BEFORE anything changes, so the change is provable
- [ ] #3 After the change, a tap queued beyond the old window is accepted, flagged, and visible as flagged in the admin panel
<!-- AC:END -->
