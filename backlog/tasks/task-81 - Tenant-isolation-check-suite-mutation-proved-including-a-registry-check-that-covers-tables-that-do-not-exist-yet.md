---
id: TASK-81
title: >-
  Tenant isolation check suite, mutation-proved, including a registry check that
  covers tables that do not exist yet
status: To Do
assignee: []
created_date: '2026-08-12 05:50'
updated_date: '2026-08-12 05:52'
labels:
  - security
  - testing
  - multi-tenancy
dependencies:
  - TASK-77
  - TASK-79
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: high
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The safety net for decision-32. Design: backlog/docs/MULTI-TENANCY.md section 1.7, which contains the exact SQL.

Cross-tenant leakage is the unrecoverable failure in this product. A check whose negative case cannot fail is not a check, and this project has been bitten three times by exactly that (a hung Chrome, a hung demo server, labels that existed but were wrong). So every check below ships WITH its mutation.

CHECK A - the registry check. One query over pg_class / pg_policies / information_schema.columns asserting that every table in public outside {tenants, deleted_tenants, schema_migrations} has a NOT NULL tenant_id, relrowsecurity, relforcerowsecurity and at least one policy. Must return zero rows.
  This is the item that answers 'someone adds a table next year and forgets'. They cannot: migration 007 adding an unprotected table fails CI on the day it is written. Nothing else in the suite has that property.

CHECK B - the red-team check. Seed tenants A and B with deliberately similar-looking data (same building name, same worker first name - so a leak is visible rather than plausible). As nfc_app inside withTenant(A), for EVERY table assert:
  - SELECT count(*) WHERE tenant_id = B is 0
  - UPDATE of a B row affects 0 rows
  - DELETE of a B row affects 0 rows
  - INSERT stamped tenant_id = B is rejected by WITH CHECK

CHECK C - the grep gate. set_config('app.tenant_id' may appear in server/lib/db.js and nowhere else in server/. Crude, ~5 lines, and it closes the one bypass the runtime role genuinely has: it can set its own GUC.

CHECK D - the context gate. A handler invoked with no tenant context throws; assert the throw.

FOUR MUTATIONS, each must turn A or B RED. A mutation that leaves the suite green means the corresponding mechanism is decorative and must be reported as such:
  1. DROP POLICY on one table -> A (missing policy) and B (rows visible)
  2. NO FORCE ROW LEVEL SECURITY on one table + connect as the owner -> proves FORCE is load-bearing
  3. connect as nfc_owner instead of nfc_app -> proves the role split is load-bearing
  4. set_config(..., false) instead of true -> proves transaction-local scoping is load-bearing

Runs against nfc_demo only. demo/db-guard.mjs already refuses anything else and its guards are mutation-tested; reuse it rather than writing a second guard. Production is READ-ONLY.

Wire into the existing check suite so CI runs it (TASK-56 makes a skip a failure - this suite must not be skippable).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Registry check returns zero rows on a correctly migrated nfc_demo, and names the offending table when it does not
- [ ] #2 Red-team check covers every table in the registry - derived FROM the registry, not from a hand-written list, so a new table is covered automatically
- [ ] #3 All four mutations are executed and each is shown to turn the suite RED; the run output for each is pasted into the task notes
- [ ] #4 The suite refuses to run against any database other than nfc_demo, and the refusal is asserted on its WORDING, not on the exit code (a process that dials production and dies also exits non-zero)
- [ ] #5 A refusing process exits: the guard treats surviving 5 seconds as failure, matching demo/check-guards.sh must_refuse()
- [ ] #6 Suite is wired into CI and cannot be skipped silently
<!-- AC:END -->
