---
id: TASK-55
title: >-
  Implement decision-30: worker_rates history and an audit trail on every money
  edit
status: To Do
assignee: []
created_date: '2026-08-12 05:02'
labels: []
milestone: m-5
dependencies: []
priority: high
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-30 (accepted 2026-08-12) supersedes decision-28 and answers its four gate questions. Build it.

Today: workers.hourly_rate_cents is a single mutable column with no history (server/routes/admin.js:340 UPDATEs in place), and patchShift (server/routes/admin.js:1070-1110) rewrites a shift's start/end - which is money - recording no previous value, no actor, no reason. There is no audit table anywhere in server/db/migrations/.

Legal: 26 AZG (working-time records) and BAO 132 (7-year payroll retention, must reconstruct what was paid and why). Neither is satisfiable from the current schema.

THE CRITICAL PROPERTY: migration 006 seeds worker_rates with each worker's CURRENT rate at valid_from = earliest of (their earliest shift date, worker created_date). That makes the deploy arithmetically a NO-OP - every existing report reproduces exactly the number it produces today. Only future rate changes create a second period. Verify this before shipping, do not assume it.

server/ currently has NO transactions at all (pool.connect/BEGIN appear nowhere). This task introduces the withTransaction helper that audit finding P6 also needs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration 006 (additive/expand only, safe against old code) adds worker_rates(worker_id, rate_cents, valid_from, valid_to) half-open Vienna calendar dates, matching the location_contracts pattern
- [ ] #2 Backfill seeds one row per worker at their earliest shift date; a before/after diff of GET /admin/data and GET /admin/pl over every existing period shows ZERO changed values
- [ ] #3 server/lib/db.js gains withTransaction(fn) using pool.connect + BEGIN/COMMIT/ROLLBACK
- [ ] #4 Payroll (GET /admin/data hours), server/lib/reporting.js and web/lib/payroll.ts all resolve the rate from ONE shared helper joined on shift date - they must not disagree
- [ ] #5 Rounding happens at one altitude, closing audit P14: reporting.js:124 rounds per (worker,location) while admin.js:228 rounds per worker, diverging up to 0.5c x (N-1) for a worker at N buildings
- [ ] #6 workers.hourly_rate_cents KEPT as a mirror of the current row, written in the same transaction, mirroring the locations.monthly_contract_cents precedent - dropping it breaks the shipped iOS response shape
- [ ] #7 shift_edits(shift_id, admin_id, changed_at, old_start, old_end, new_start, new_end, note) written in the SAME transaction as patchShift; note is REQUIRED
- [ ] #8 worker_rate_changes(worker_id, admin_id, changed_at, old_cents, new_cents, reason, kind) with kind in (raise, correction)
- [ ] #9 Admin UI has TWO distinct actions: Record a raise (forward-dated, default) and Correct a mistake (retroactive, reason required) - reuse the buildings-form pattern
- [ ] #10 GET /admin/pl labour.rate_basis current marker and its German note are REMOVED - the limitation no longer exists and leaving them would be a new lie
- [ ] #11 Unit tests for the rate resolver across a period boundary, and for a shift on the exact valid_from date (half-open boundary)
- [ ] #12 DEMO: give a worker a raise, then show a payroll report for a PRIOR period still printing the original figure; then edit a shift and show the shift_edits row naming who, when, old value and why
<!-- AC:END -->
