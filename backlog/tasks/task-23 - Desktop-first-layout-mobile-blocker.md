---
id: TASK-23
title: Desktop-first layout + mobile blocker
status: Done
assignee: []
created_date: '2026-07-28 13:51'
updated_date: '2026-08-12 04:57'
labels:
  - obsolete
milestone: m-3
dependencies:
  - TASK-14
priority: high
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Below 1024px: full-screen message 'Admin designed for desktop.' Above: sidebar nav + main content. Nav items: Dashboard (map), Shifts, Workers, Locations, Payroll. 2-3 click max depth.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Mobile/tablet shows blocker, no admin UI leaks
- [x] #2 Desktop shows sidebar + content layout
- [x] #3 All functions reachable from sidebar in 1-3 clicks
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OBSOLETE as of decision-28 (2026-08-12). This task shipped the desktop-only blocker; decision-28 supersedes decision-7 and task-50 removed the blocker. Kept for history. Do NOT use this task's acceptance criteria as a specification — they describe reverted behaviour.
<!-- SECTION:NOTES:END -->
