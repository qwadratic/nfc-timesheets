---
id: TASK-365.22
title: >-
  Verification rig: sign in as a WORKER against a loopback server and drive
  worker flows on the simulator
status: To Do
assignee: []
created_date: '2026-10-07 12:28'
labels:
  - ios
  - verification
  - tooling
dependencies: []
parent_task_id: TASK-365
priority: high
ordinal: 306000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every iOS parity task (P1-P7, B1-B5, E1-E3) has acceptance criteria that must be DRIVEN on the simulator against a real server (AGENTS.md: one verify agent per feature drives the action matrix; never assert from source). Today no rig can do that for the WORKER app:
- the simulator has no NFC, and DemoHooks has no sign-in hook (decision-50 retired the Sign-in-with-Apple path demo/demo-server.mjs was built around);
- the existing UI-test stub (NFCTimeSheets/checks/write-tag-uitest-stub.mjs) serves two routes and only signs in an OPERATOR;
- decision-79's refusals (422 zone_unverified / unknown_location, 409), the zone cache of P1, the schedule of P4 and the delivery states of P5-P7 all need real answers.

What to build (loopback only, nothing near staging, no demo mode in the product):
1. A throwaway Postgres cluster (Postgres 18 is installed: /opt/homebrew/bin/initdb, pg_ctl) with the server migrations applied. server/lib/db.js REFUSES a superuser or BYPASSRLS role, so create an app role that is NOSUPERUSER NOBYPASSRLS.
2. server/server.js on 127.0.0.1 with a seed: one company workspace, a few buildings with zones (verified and unverified), one worker, one operator, and a worker enrolment code (decision-63: five digits) - via the existing server/bin scripts or SQL.
3. demo/tls-front.mjs + a throwaway CA trusted by the booted simulator (recipe: backlog/docs/DEMO.md section 3.1; keep keys in the session scratchpad, delete after).
4. The app built with TS_API_HOST / TS_TAG_HOST pointing at the front, and an XCUITest helper that signs in as the worker through the real code form (CodeSignInSection) - the same way WriteTagRestartUITests signs in an operator.
5. A script that tears everything down (processes, cluster, certs, simulator clone).
Out of scope: any change to the product for the sake of the rig.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One command (or one documented sequence) brings the rig up and down, leaving no process, port, certificate or database behind
- [ ] #2 A UI test signs in as a worker through the real code form and reaches the idle screen
- [ ] #3 The rig can seed a verified zone, an unverified zone and a deactivated zone, and flip them between runs
- [ ] #4 The P2 criteria #2-#11 and the P1 matrix in TASK-365.2 are driven with it and ticked
- [ ] #5 Nothing in the product changes for the rig; no staging host is ever contacted
<!-- AC:END -->
