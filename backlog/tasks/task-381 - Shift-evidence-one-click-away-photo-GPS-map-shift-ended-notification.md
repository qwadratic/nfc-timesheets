---
id: TASK-381
title: 'Shift evidence one click away: photo + GPS map + shift-ended notification'
status: In Progress
assignee: []
created_date: '2026-11-13 11:58'
labels:
  - web
  - shift-evidence
dependencies: []
ordinal: 313000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner tested a shift with 5-min GPS and photo proof and could not find the evidence: it was buried inside the Correction drawer behind a collapsed details element, the photo was a bare link and GPS a lat/long table. Admins need to see proof directly from the shift list and be told when a shift ends. The shift GPS/photo policy was also only editable inside the /setup wizard, so the owner could not find where to change it mid-operation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every shift row with a client_uuid shows a visible Foto & GPS button in the shifts list, no Correction drawer needed
- [ ] #2 Evidence view shows the photo inline and an interactive map with one point per GPS sample, connected in time order, instead of a coordinate table
- [ ] #3 /shifts/?evidence=<client_uuid> opens that shift's evidence directly
- [ ] #4 Admin sees a notification when a worker ends a shift, linking straight to that shift's evidence
- [ ] #5 Shift GPS interval and photo-proof policy are editable from the account page, not only /setup
- [ ] #6 All new strings exist in web/messages/de.json and en.json; pnpm verify passes
<!-- AC:END -->
