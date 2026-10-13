---
id: TASK-339
title: >-
  Android: simplify cleaner navigation, restore language choice and verify tag
  activation
status: Done
assignee:
  - '@codex'
created_date: '2026-09-22 09:08'
updated_date: '2026-09-22 10:16'
labels:
  - android
  - ux
  - nfc
dependencies: []
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner reports clutter after login, missing German choice and tags that remain unknown after writing and naming. Start from merged main, preserve separate operator authentication and verification before clock-in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DE and EN selection persists across relaunch and applies to screens and notifications
- [x] #2 Simple worker navigation keeps hours, materials and settings reachable and supports operator access without worker logout
- [x] #3 Tag lifecycle has clear next actions and regression coverage for identified failures
- [x] #4 Build and relevant checks pass; emulator journeys and physical NFC limits are documented
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Inspect current behavior and decisions. 2. Restore language choice and simplify worker navigation. 3. Fix reproduced activation and navigation defects. 4. Run emulator journeys, checks and dedicated review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner clarified: Google Play build 29 shows Open URL while already inside the app until Scan tag manually is opened. MainActivity currently has no reader mode. Add automatic foreground worker-only scanning, pause it in operator UI, retain shared deduplication and strict tag parsing.

Worker feature emulator pass verified DE/EN/system, persisted locale, translated ongoing notifications, three-tab navigation, material draft retention, reachable History Back and separate operator session. Dedicated review found and fixed a foreground roster/tap state race. Tag verification found missing bound-zone heading and misleading confirmed UI for unverified queued starts; fixes preserve existing retry/offline-time policy. Final physical NFC test remains unavailable on emulator.

Tag feature passed real local API/PostgreSQL journeys with debug card simulations: write/report/bind/verify, wrong card refusal and no operator shifts. Before activation, queued UUID ad0fc665-ddfc-453c-b4ad-1faf19395d6a remained saved; pending UI and notifications passed DE/EN. Activation and Refresh delivered that exact original-time row once; later tap closed it. Final debug/release/AAB builds PASS; branding OK without TODO; API suite PASS on full rerun; reader lifecycle, writer/raw/401 checks PASS. Broad checks remain non-green: core path assertion and 4 web pnpm verify path assertions on Windows, Android lint 129 errors. These were not suppressed; see docs/android-worker-verification.md. Physical NFC/Play build and older Android locale fallback not device-verified. True before/after gallery captured using main UI plus isolated local transport, then latest app restored.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Simplified worker navigation and added DE/EN choice, worker-to-operator access, foreground automatic tag reading, direct activation CTA, correct building labels and honest pending-shift UI without losing offline time. Verified via dedicated worker/tag emulator journeys, real local API/PostgreSQL, APK/AAB builds and ADR review. Screenshot comparison and precise check/device limits documented. No push or deployment.
<!-- SECTION:FINAL_SUMMARY:END -->
