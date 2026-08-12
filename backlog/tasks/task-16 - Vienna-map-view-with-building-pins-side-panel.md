---
id: TASK-16
title: Vienna map view with building pins + side panel
status: In Progress
assignee: []
created_date: '2026-07-28 13:49'
updated_date: '2026-08-12 05:05'
labels:
  - web
  - ux
milestone: m-6
dependencies:
  - TASK-15
  - TASK-2
priority: low
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dashboard home = map of Vienna (Leaflet or Mapbox free tier). Buildings as pins with thumbnails. Click pin -> side panel slides in with building summary: name, address, photo, total hours, top 5 metrics. Period selector: this week/month/quarter/year/all (5 views, default this week).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Map renders centered on Vienna
- [ ] #2 Each building appears as pin at coordinates
- [ ] #3 Pin shows thumbnail photo or placeholder
- [x] #4 Side panel slides in with summary on click
- [x] #5 Period selector switches all displayed metrics
- [x] #6 Panel closable, map interactive behind it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AUDIT 2026-08-12 — this is no longer a build task. The map IS built and lives on web/app/analytics/page.tsx (web/lib/map.ts:24,153), NOT on web/app/page.tsx as this task's original note claims. That stale note is what caused task-48 to be filed as a duplicate. AC#1-3 are blocked by ONE ops defect, not by missing code: ops/deploy.sh:44 passes only NEXT_PUBLIC_DEFAULT_LOCALE=de to the build, so the Google Maps key is never inlined into the production bundle. Fixing that one line plus installing GOOGLE_GEOCODING_KEY on the server unblocks AC#1-3 here AND AC#1 on task-17.
<!-- SECTION:NOTES:END -->
