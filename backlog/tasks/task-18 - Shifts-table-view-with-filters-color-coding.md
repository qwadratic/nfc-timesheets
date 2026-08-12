---
id: TASK-18
title: Shifts table view with filters + color coding
status: In Progress
assignee: []
created_date: '2026-07-28 13:50'
updated_date: '2026-08-12 05:05'
labels:
  - web
milestone: m-5
dependencies:
  - TASK-15
  - TASK-3
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Table: worker, building, date, start, end, duration, status. Filters: worker, building, date range, status. Server-side pagination 50/page. Joined view (names not IDs). manualFinish=amber row, needsCorrection=orange row. URL-persisted filters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All shifts visible with human-readable names
- [ ] #2 Filters narrow results, URL-persisted
- [ ] #3 Pagination works with >100 shifts
- [x] #4 Color coding visible at a glance
- [ ] #5 Sorting by any column
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AUDIT 2026-08-12. Shipped: joined human-readable names and colour coding (web/app/shifts/page.tsx, 36.6K). NOT shipped: AC#2 (URL-persisted filters) and AC#5 (sorting) — the file contains no useSearchParams and no sort handlers. WARNING on AC#3 (server-side pagination): the code has since deliberately decided AGAINST it. web/app/shifts/page.tsx:54-60 argues the unbounded client-side fetch is intentional because 'a server-bounded fetch would destroy the only fact that tells an empty FILTER apart from an empty DATABASE'. Do not implement AC#3 without superseding that reasoning first — it is a real argument, not an oversight.
<!-- SECTION:NOTES:END -->
