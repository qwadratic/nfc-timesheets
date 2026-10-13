---
id: TASK-337
title: Implement approved web admin usability improvements
status: Done
assignee:
  - '@codex'
created_date: '2026-09-19 18:16'
updated_date: '2026-09-19 18:41'
labels:
  - web
  - ux
dependencies: []
ordinal: 254000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner approved the scoped proposals in TASK-336. Improve clarity, information density and daily navigation on the existing static Next.js admin. Preserve hosting and filesystem path conventions; do not change slash handling in verification. Work on codex/app-improvements above Android 8a32cc7 with separate logical commits; no push, PR or merge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Worker access and building-zone guidance match current decisions in German and English without changing authentication or NFC behavior.
- [x] #2 Workers list is visible sooner and supports search and status filtering; onboarding and SMS controls remain reachable.
- [x] #3 Locations show compact summaries and opening zones exposes the section with operator-only guidance and all existing actions preserved.
- [x] #4 Shift state filters and actionable summaries preserve URL context and distinguish running shifts from exceptions.
- [x] #5 Browser feature verification and decision/code review are recorded; pnpm verify and branding checks are run with existing failures reported honestly.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Correct obsolete guidance and missing-email alerts. 2. Improve worker list, search, filters and grouped form. 3. Compact location summaries and make zones reachable. 4. Add shift state controls and contextual summary links. 5. Polish shared spacing. 6. Run browser feature checks and dedicated decision review, resolve findings, run verification, and commit each logical slice. Keep scripts/check.mjs slash behavior untouched as requested.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented separate commits above Android8a32cc7 on codex/app-improvements. Corrected obsolete access/zone guidance; URL-preserved roster search includes contact and login identities, status filters, settings disclosure, grouped form;5column locations with zones focus/history; shift state filter and exact dashboard links; responsive labels refresh on language change. New strings synchronized DE/EN.
Dedicated feature agents drove workers, locations and shifts/dashboard in real browsers against synthetic read-only fixtures. Parent checked DE/EN, light/dark and390px viewport, and captured4matched1280x720 before/after pairs plus4additional screenshots. Files: docs/media/app-improvements/index.html; archive docs/media/app-improvements-screenshots.zip (ignored local artifacts).
Review gate read every ADR and passed after fixes for zero-count link, login identity search coverage, navigation-query PII scrubbing and44px disclosure targets. Additional responsive-locale fix reviewed and browser-proved by header/data-label equality after DE->EN.
Checks: pnpm build/typecheck pass; pnpm lint has one existing optional-chain warning payroll/page.tsx:749. pnpm verify run on final implementation: exactly4baseline Windows separator failures (one-map path; two locations path lookups; worker-rate path lookup). No slash behavior changed. New URL roundtrip and navigation PII assertions plus i18n parity pass. check-branding OK with no TODO.
Limitations: no real DB available; successful writes/SMS/email/NFC/production not verified or changed. Read-only fixture refusals and form validation exercised; live-code replacement/revoke unavailable without live code. No push/PR/merge. .idea/ and Android daemon JVM properties remain untracked and excluded.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Approved admin usability improvements implemented in separate local commits, feature-tested in browsers and independently reviewed. Before/after screenshot gallery and archive delivered. Build passes; four existing Windows path checks remain explicitly reported, with path behavior preserved.
<!-- SECTION:FINAL_SUMMARY:END -->
