---
id: TASK-338
title: Audit and harden admin management and building reporting flows
status: Done
assignee:
  - '@codex'
created_date: '2026-09-19 18:55'
updated_date: '2026-09-19 21:33'
labels: []
dependencies: []
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner requests a logic audit and fixes for worker/company/building/zone management, address accuracy and suggestions, building map summary and owner reporting access. Continue local codex/app-improvements commits without deployment or push. Preserve operator-only zone creation and existing hosting/path conventions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Confirmed lifecycle, identity and sharing defects are fixed with targeted regression evidence.
- [x] #2 Address edits cannot silently preserve an obsolete pin and invalid geocoder coordinates are rejected.
- [x] #3 Building summary offers a direct owner-report access path and address assistance degrades safely when unavailable.
- [x] #4 Browser workflows, automated checks and independent review recorded with backend/provider limitations explicit.
- [x] #5 Backlog.md is usable as an installed command and existing project workflow is preserved.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Trace frontend to API and ADRs; record concrete defects. Fix lifecycle/report access and pin integrity in separate commits with regression checks. Add scoped address assistance and contextual owner-report entry. Verify affected browser flows and current checks; required dedicated review after implementation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Full server/check-api.js passes on isolated local PostgreSQL 16.14, including new regression cases for form deactivation, cross-company grant refusal, stale pins, partial coordinate rejection and late geocoder replies. Backlog 1.52.0 standalone executable installed to user Programs and user PATH; existing AGENTS CLI workflow retained. No production data or hosting touched.

Final verification: full API suite PASS on genuine isolated PostgreSQL16, dedicated worker/sharing/building browser agents PASS with DB readback, all-ADR review approved and branding all OK. pnpm verify retains exactly four original Windows path failures; separate lint/typecheck/static build PASS (baseline payroll optional-chain warning only). Real Google key/provider unavailable; manual fallback verified. Final DE/EN wizard/cascade wording also driven in browser. Evidence docs/ADMIN-LOGIC-AUDIT.md; screenshot gallery and 20-file ZIP in docs/media/app-improvements. No push/deploy/PR/merge.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Hardened lifecycle access, company-scoped owner links, partial worker identity saves and address/pin races; added owner-report entry and optional address suggestions with manual fallback. Verified API, browser flows and independent ADR review; external Google and baseline Windows-check limits explicitly recorded.
<!-- SECTION:FINAL_SUMMARY:END -->
