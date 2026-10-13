---
id: TASK-370
title: >-
  Triage the stranded Dd backlog lineage: 82 tasks (54-113+), decisions
  25/29-36, 13 docs, the 12 Aug admin UX pass
status: To Do
assignee: []
created_date: '2026-10-13 05:21'
labels:
  - backlog
  - triage
  - archive
dependencies: []
priority: medium
ordinal: 308000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Branch Dd (local only until 2026-10-13, now archived as origin/archive/dd-2026-08-13 @ d3d8522, 6 commits 2026-08-12/13, base 9b947e9, 637 commits behind main) holds work that never reached main:

BACKLOG RECORDS: 82 tasks with ids absent from main (54-113 and more; 66 of them To Do, operations hardening: APP_KEY rotatable key set t54, CI t56, offsite backup t57, metrics t58, deploy health gate/rollback t60, GDPR t61, alerting t62, incident process t64 ...), decisions 25 (tombstone), 29-36 (admin panel on a phone, worker rate history + audit trail, SMS OTP identity, multi-tenancy RLS, zones as locations rows, m2-per-hour planning figure, in-app tag writing, admin assistant catalogue), 13 docs (UX-AUDIT, UX-PLAN, DESIGN-SYSTEM, IA-AND-JTBD, MULTI-TENANCY, SMS-AUTH, ZONES-AND-TAG-WRITING, ...) and milestones m-5/m-6. None of decisions 25/29-36 is referenced anywhere on main; main later re-decided several of the same questions under other ids (e.g. zones decision-43, tag writing decision-49, company workspaces decision-72) so MOST are probably superseded - each needs a verdict.
CODE: the 12 Aug admin UX pass (web/app/{payroll,pl,shifts,workers,...}, 19 web files that ALSO changed on main since, so a straight merge conflicts), web/lib/{params,load}.ts, web/components/DataState.tsx, web/scripts/check-design-tokens.mjs, demo/ux-*.mjs recorders, ops/sync-secrets.sh, docs/fleet-schemas, brand assets.

DO: per item decide import / supersede / drop; import the keepers as NEW ids on this branch (do not resurrect the old ids blindly); cherry-pick only the code worth keeping as its own tasks. Then delete the local Dd and, once nothing is left to mine, the archive ref.
<!-- SECTION:DESCRIPTION:END -->
