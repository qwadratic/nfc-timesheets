---
id: TASK-368
title: Active-shift location and camera proof on Android and iOS
status: In Progress
assignee:
  - '@codex'
created_date: '2026-10-10 18:42'
updated_date: '2026-10-10 19:06'
labels: []
dependencies: []
documentation:
  - docs/shift-evidence.md
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Administrators need configurable periodic position capture during work and optional mandatory fresh camera evidence before a worker finishes a shift. Develop in isolated codex/shift-evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Company admin configures location interval and proof requirement; both default off
- [ ] #2 Android and iOS collect location only during active shifts with visible permissions
- [ ] #3 Camera photo required before successful close; cancellation preserves active shift
- [ ] #4 Tenant isolation, retries, DE/EN and platform limits verified and documented
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Agree contracts; implement server and mobile clients; isolated admin settings; feature verification and independent decisions review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in isolated codex/shift-evidence. Admin browser save/reload/off and DE/EN verified; pnpm verify passes. Android debug build and core checks pass; real emulator location persisted at 60.098-second cadence in background. PostgreSQL/HTTP evidence suite passes. Full legacy API has same serial/name uniqueness failure on original HEAD41925c9 baseline and feature branch. Independent all-decisions static review corrected lost-response recovery and rapid NFC gate. Release remains blocked: iOS Swift/Xcode unavailable, mandatory gate says checks: swift not found. Native feature matrices recorded in docs; do not mark Done from static iOS inspection.

Android emulator confirmed fresh camera cancel/retake/success, private admin photo rendering, service stop after close, and recovery when a committed close response was dropped. Transport retry was driven; persisted-proof manual retry and remaining native edge paths are explicitly unverified in feature reports. No production deployment performed.

Final Android location checks: disabled policy produced no samples; permission denial showed actionable German error; revocation stopped service; restored permissions resumed service. Real sign-out stopped service and a subsequent injected location produced no new row. iOS and physical-device background execution remain pending.
<!-- SECTION:NOTES:END -->
