---
id: TASK-336
title: Audit web admin UX and propose scoped improvements
status: Done
assignee:
  - '@codex'
created_date: '2026-09-19 18:10'
updated_date: '2026-09-19 18:12'
labels:
  - web
  - ux
dependencies: []
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner requested a browser audit and concrete visual and usability proposals before approving admin implementation. Branch codex/app-improvements must retain Android HEAD 8a32cc7. No push, PR or merge; later approved admin changes must be separate commits; never stage .idea or android/gradle/gradle-daemon-jvm.properties.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Branch starts at unchanged Android commit 8a32cc7.
- [x] #2 Current admin is inspected in a real browser with data and backend verification limits stated.
- [x] #3 Baseline pnpm verify and branding results are reported accurately.
- [x] #4 Prioritized concrete improvements are presented for approval before implementation.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Read current code and decisions, run baseline checks, inspect static export in the in-app browser on read-only synthetic data, and present scoped proposals. No UI implementation in this audit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Browser evidence: inspected actual static Next.js export at 127.0.0.1:8080 in Codex in-app browser at 1280x720. Viewed login, dashboard, workers, worker edit drawer, locations, zone empty state, shifts, payroll, material empty state and clients; German/dark and English/light. Used temporary loopback read-only synthetic API, not production. Writes rejected. Did NOT verify backend mutations, authentication, real query filtering, payroll arithmetic, Google Maps, populated P&L/analytics, mobile or large datasets.

Confirmed: workers code explanation and email field help still describe Apple login, while decision-50 retires it. Dashboard counts missing legacy workers.email as access problems. Home objectsNoZone says building tags still start shifts, contradicting locations and decision-69. Workers first data row falls below 1280x720 viewport due to lengthy onboarding text and SMS limit form. Locations has eight columns; short names wrap across three lines and individual rows contain long repeated paragraphs. Opening zones adds content below the building list while focus remains on the triggering button. Empty zone copy omits a clear instruction to create/bind in the operator app (decision-54). Shifts has worker/location/period filters and sorting, but no visible status picker although URL state filters exist.

Baseline: pnpm verify FAILED with four existing Windows path failures in web/scripts/check.mjs: HomeMap path comparison plus locations tag/verification and worker-rate source lookup. sourceFiles uses node:path join but comparisons use forward slashes. No fix applied. Separate pnpm lint passed with one existing useOptionalChain warning at web/app/payroll/page.tsx:749; pnpm typecheck and pnpm build passed. node ops/check-branding.mjs passed, no TODO lines.

Proposed separate implementation commits, ALL pending owner approval:
0. Normalize check source paths on Windows and rerun full pnpm verify.
1. Correct obsolete access and zone guidance and false missing-email alerts, using current login capabilities and facts rather than assuming credentials; DE and EN together.
2. Workers: list near top, collapsible onboarding help and advanced SMS setting, search/status filters, grouped edit form (person/contact, login, pay).
3. Locations: compact summary columns, details in existing panel, clear operator-only create/bind instructions for empty zones, reveal/focus opened zone section.
4. Shifts/dashboard: visible quick state filters, clickable actionable counts, distinguish normal running shifts from exceptions, preserve URL filter context and map/list/ledger architecture.
5. Shared visual polish: consistent spacing, table alignment, readable short badges, compact filter bars and clear primary/secondary actions in both themes. Keep visible financial caveats, accessibility and all actions.

No UI code changes. No push, PR or merge. Preserve Android 8a32cc7 and exclude .idea/ and android/gradle/gradle-daemon-jvm.properties. Accepted mobile decision-28 supersedes decision-7; summary docs are stale.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Completed browser UX audit and prepared six scoped proposals for owner approval. Baseline Windows verify failure is documented; separate lint, typecheck, build and branding results recorded. UI implementation remains unapproved and untouched.
<!-- SECTION:FINAL_SUMMARY:END -->
