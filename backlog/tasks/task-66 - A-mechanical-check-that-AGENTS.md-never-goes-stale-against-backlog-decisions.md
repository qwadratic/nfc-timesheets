---
id: TASK-66
title: A mechanical check that AGENTS.md never goes stale against backlog/decisions
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-5
dependencies:
  - TASK-56
priority: medium
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The AGENTS.md decision checklist is explicitly framed there as the review gate's safety net, and on 2026-08-12 it was found EIGHT DAYS stale: it stopped at decision-24 while 26, 27, 28 and 29 were binding, and it still listed decision-7 (mobile blocker) as active after decision-29 reversed it. Agents reading it built against reversed decisions.

It was fixed by hand in this session. It will go stale again, because nothing enforces it. This task makes that impossible rather than merely discouraged.

Same class of drift, same fix: state.md was two weeks stale and claimed Not deployed, PM2, and Android research-only. It has been reduced to a pointer. AGENTS.md cannot be reduced to a pointer, so it needs a check.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ops/check-decisions.mjs asserts every file in backlog/decisions/ appears in the AGENTS.md checklist, and that no decision marked superseded is listed as binding
- [ ] #2 It also asserts decision IDs are unique and contiguous - the 2026-08-12 audit found TWO files claiming decision-28 and a missing decision-25
- [ ] #3 Wired into CI (task-56) and into the pre-commit hook
- [ ] #4 DEMO: add a decision record without updating AGENTS.md and show the check failing
<!-- AC:END -->
