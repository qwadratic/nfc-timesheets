---
id: TASK-80
title: 'Server: zone CRUD, building() rollups, and auto_closed only across buildings'
status: To Do
assignee: []
created_date: '2026-08-12 05:50'
labels:
  - zones
  - server
dependencies:
  - TASK-78
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: high
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The one BEHAVIOURAL change zones make to the running system, plus the CRUD to feed it.

TODAY (server/routes/app.js): the app closes an open shift with auto_closed=true when the
worker taps a DIFFERENT building without tapping out. auto_closed AND corrected_at IS NULL is
the 'unresolved' predicate that forces a resolution screen before payroll sees the shift.

Moving between zones INSIDE one building is the opposite of that: a deliberate tap on a
deliberate tag by a person standing in front of it. Flagging it routes a normal working day
through the correction screen several times a shift, and a prompt that fires constantly is a
prompt nobody reads.

```
tap target T while shift S open:
  building(T) == building(S)  -> close S auto_closed = FALSE, open new at T   (zone move)
  building(T) != building(S)  -> close S auto_closed = TRUE,  open new at T   (unchanged)
  building(x) = COALESCE(x.parent_id, x.id)
```

The decision is made SERVER-SIDE. The app does not know two UUIDs share a parent and must not
be taught - shipping the hierarchy to every phone means keeping it in sync there. decision-19:
the server is authoritative for open shifts.

Also: GET /me returns only buildings in `locations` as today; zone rows must not appear in
that roster, or a worker-facing picker materialises by accident.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Admin zone CRUD: create/edit/deactivate a zone under a building. Rejects a parent that is itself a zone with a 400, not a 500
- [ ] #2 building(x) = COALESCE(parent_id, id) exists in exactly ONE place and every rollup uses it
- [ ] #3 Zone tap inside the same building sets auto_closed = FALSE; different building keeps auto_closed = TRUE. Decided server-side, from the DB, never from a request field
- [ ] #4 MUTATION TEST: force building(x) to return id (i.e. break the parent lookup) and the same-building case must go RED in check-api.js
- [ ] #5 GET /me (worker roster) returns ONLY parent_id IS NULL rows - a zone never reaches a worker's app as a pickable location
- [ ] #6 Existing shifts against a building still resolve, total and price unchanged: an assertion on the 8 pre-migration rows
- [ ] #7 Geocoding is skipped for zones: no Google call, no ZERO_RESULTS row
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 server/check-api.js green, including every new negative case
- [ ] #2 No production write
<!-- DOD:END -->
