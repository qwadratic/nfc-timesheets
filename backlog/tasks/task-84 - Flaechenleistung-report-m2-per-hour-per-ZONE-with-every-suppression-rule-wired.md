---
id: TASK-84
title: >-
  Flaechenleistung report: m2 per hour per ZONE, with every suppression rule
  wired
status: To Do
assignee: []
created_date: '2026-08-12 05:50'
labels:
  - zones
  - web
  - server
  - reporting
dependencies:
  - TASK-80
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: medium
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Flaechenleistung = area_dm2 / 100 / (payable_minutes / 60).

WHAT IT IS FOR: pricing and planning. Quoting a 400 m2 stairwell is guesswork today and
becomes arithmetic once there is a historical rate for stairwells we already clean.

WHAT IT IS NOT FOR: rating people. It is one GROUP BY worker_id away from a staff league
table and somebody will write that query. decision-34 is the record; this task is the
mechanisms. A warning in a doc is not a control.

Screen lives NEXT TO CONTRACTS, not next to payroll - placing it on the payroll screen makes
the wrong reading the obvious one.

The n=5 and 3x thresholds are INVENTED (8 shifts in production, nothing calibrated them).
Put them in ONE named constant each, cited back to decision-34, so recalibration is not a
hunt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 m2/h is computed and displayed PER ZONE. There is no per-worker productivity screen and no export that yields one - grep the export code paths and say so in the notes
- [ ] #2 A per-worker figure appears only INSIDE a single zone, against that zone's own median. Never across zones, never as a ranking
- [ ] #3 Below n = 5 shifts the panel shows 'n = 3 - zu wenig Daten' and NO number at all. Empty state says how many more are needed ('noch 2 Schichten'), not merely 'no data'
- [ ] #4 Shifts with auto_closed AND corrected_at IS NULL are excluded (decision-10). Payroll and this report must not disagree about what a real hour is
- [ ] #5 Segments longer than 3x the zone median are excluded, counted as 'unplausibel', and THAT COUNT IS SHOWN. An invisible exclusion is a lie
- [ ] #6 The building figure is shown BESIDE the zone rows, never instead of them
- [ ] #7 A zone with area_dm2 NULL is absent from the report and is NEVER treated as 0 m2
- [ ] #8 MUTATION TEST each suppression: set n=4 and the number must vanish; set an 8h auto-closed unresolved shift and it must not move the rate; set one 4x-median segment and the unplausibel counter must go to 1. Each must go RED when its rule is removed
- [ ] #9 de/en key parity; the caveat text is ON THE SCREEN, not only in a doc
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 pnpm check + check-api.js green
- [ ] #2 No production write
<!-- DOD:END -->
