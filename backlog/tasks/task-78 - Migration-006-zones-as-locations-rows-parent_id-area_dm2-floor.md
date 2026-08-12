---
id: TASK-78
title: 'Migration 006: zones as locations rows (parent_id, area_dm2, floor)'
status: To Do
assignee: []
created_date: '2026-08-12 05:49'
updated_date: '2026-08-12 06:14'
labels:
  - zones
  - server
  - db
dependencies: []
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: high
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add the zone hierarchy to `locations` without touching a single existing row (decision-33).

```sql
ALTER TABLE locations
  ADD COLUMN parent_id UUID REFERENCES locations(id),   -- NULL => building
  ADD COLUMN area_dm2  INTEGER CHECK (area_dm2 > 0),    -- square DECIMETRES, integer
  ADD COLUMN floor     TEXT;                            -- 'EG', '1. OG', 'Keller'
CREATE INDEX locations_parent_id_idx ON locations (parent_id);
```

WHY one table and not a `zones` table: measured in ZONES-AND-TAG-WRITING.md 1.1. A second
tag parameter `&z=<uuid>` costs 103 NDEF bytes against 46 available on the tag already
deployed at HOIV. Zones must share the `?l=` identifier namespace, so they share the table.

Area is INTEGER square decimetres, not NUMERIC: `pg` returns NUMERIC to JS as a string and
the first consumer that forgets to parse it is a silent NaN. Same rule as money-in-cents.

ponytail: adjacency list, hard depth cap of 1. CEILING: no ltree, no closure table, no
recursive rollup. UPGRADE PATH: the cap is a trigger; lift it only when a real third level
exists, and price the tree widget before you do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration 006 applies cleanly on a copy of production and changes ZERO existing rows (prove it: row count and a checksum of locations before/after are identical)
- [ ] #2 parent_id NULL => building, NOT NULL => zone. A trigger REJECTS a zone whose parent is itself a zone (depth cap of 1)
- [ ] #3 CHECK constraint: a zone may not carry client_id, monthly_contract_cents, target_minutes_per_month, lat or lng
- [ ] #4 A trigger REFUSES a location_contracts row whose location_id is a zone (decision-6, decision-30 keep money at the building)
- [ ] #5 MUTATION TEST: each of the three guards above is proven RED by an attempted violating INSERT/UPDATE in check-migrate.js. A guard whose negative case cannot fail is not a guard
- [ ] #6 Migration is idempotent / re-runnable, matching the style of 005
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 server/db/check-migrate.js passes, including the three new negative cases
- [ ] #2 No production write. Verified against a local nfc_demo copy only
<!-- DOD:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-08-12 06:14
---
MIGRATION NUMBER ALLOCATION (planning run, 2026-08-12): 006 = phone identity (TASK-121, decision-31), 007 = zones (this task), 008 = tenancy (TASK-77). Renumber to 007. Never run two migrations in parallel against the same database.
---
<!-- COMMENTS:END -->
