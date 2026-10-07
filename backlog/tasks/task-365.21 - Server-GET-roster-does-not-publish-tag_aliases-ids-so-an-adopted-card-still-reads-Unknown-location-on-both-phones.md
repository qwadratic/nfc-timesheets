---
id: TASK-365.21
title: >-
  Server: GET /roster does not publish tag_aliases ids, so an adopted card still
  reads "Unknown location" on both phones
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - server
  - android
  - ios
dependencies: []
parent_task_id: TASK-365
priority: low
ordinal: 305000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
server/routes/app.js roster() publishes zones only. A card adopted by an existing zone through tag_aliases (migration 008) resolves server-side but the phones cannot map its id to a building. Needs a server change and probably a decision (decision-44 area); found while planning P1. Affects the HOIV grandfathered card first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decide whether roster should publish alias ids (or the zone they map to)
- [ ] #2 Both phones resolve the alias to its building name
<!-- AC:END -->
