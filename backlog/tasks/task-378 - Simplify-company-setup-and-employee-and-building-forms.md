---
id: TASK-378
title: Simplify company setup and employee and building forms
status: To Do
assignee: []
created_date: '2026-10-20 18:20'
labels: []
dependencies: []
priority: high
type: enhancement
ordinal: 311000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner wants a novice-friendly admin: an obvious way to add the whole team and every building without a wall of optional fields. The work was first done in the stranded proximata-era lineage (local TASK-373 there, never committed) and is re-recorded here before it lands. Keep authentication, NFC, pay and customer data semantics unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Employee creation starts with name and required positive rate; optional contact and login fields stay available, keep their values and validation, and open when they hold an error
- [ ] #2 Building creation needs no hand-made technical handle and no contract step; customer, contract and status editing remain available
- [ ] #3 Setup lets the admin add several buildings and employees in a row and shows saved counts per step
- [ ] #4 Main's later choices stay: no Manage-all links or address search in setup, manual building handles still listed, SMS/email login fields only behind their flags (decision-78)
- [ ] #5 DE and EN messages complete; tsc, biome, check.mjs, next build and check-branding pass; journeys driven in a browser against isolated PostgreSQL
<!-- AC:END -->
