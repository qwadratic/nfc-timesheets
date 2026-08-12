---
id: TASK-17
title: Google Street View for building photos
status: In Progress
assignee: []
created_date: '2026-07-28 13:49'
updated_date: '2026-08-12 05:05'
labels:
  - web
  - api
milestone: m-6
dependencies:
  - TASK-2
priority: low
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On building creation or first view, fetch Street View static image by address/coordinates. Cache in DB. No coverage -> text-on-color placeholder. Admin can optionally upload replacement photo.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Buildings with Street View show real photo
- [x] #2 Buildings without coverage show styled placeholder
- [ ] #3 Admin can override with uploaded photo
- [x] #4 Photos cached, not refetched per page load
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AUDIT 2026-08-12. The Street View gate is correct and shipped: web/lib/map.ts:195-208 returns null unless street_view_status === 'OK'; status is persisted at server/lib/geocode.js:138 and server/routes/admin.js:73,560. AC#1 is blocked externally (Street View Static API not enabled on the Google project) — an owner console action, not a code task. AC#3 (admin uploads a replacement photo) was never built; there is no upload handler in server/routes/admin.js. Decide whether AC#3 is still wanted before working this.
<!-- SECTION:NOTES:END -->
