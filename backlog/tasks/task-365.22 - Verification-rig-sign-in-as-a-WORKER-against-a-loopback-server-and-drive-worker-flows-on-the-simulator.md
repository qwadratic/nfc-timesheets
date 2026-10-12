---
id: TASK-365.22
title: >-
  Verification rig: sign in as a WORKER against a loopback server and drive
  worker flows on the simulator
status: In Progress
assignee: []
created_date: '2026-10-07 12:28'
updated_date: '2026-10-12 17:50'
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
- [x] #1 One command (or one documented sequence) brings the rig up and down, leaving no process, port, certificate or database behind
- [x] #2 A UI test signs in as a worker through the real code form and reaches the idle screen
- [x] #3 The rig can seed a verified zone, an unverified zone and a deactivated zone, and flip them between runs
- [ ] #4 The P2 criteria #2-#11 and the P1 matrix in TASK-365.2 are driven with it and ticked
- [x] #5 Nothing in the product changes for the rig; no staging host is ever contacted
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-12 BUILT AND RUN. Commits 8070c4f + b688541 on branch ios-verification-rig (from ios-worker-parity d79dcd9). Everything is in ops/ios-rig/ (README.md has the commands, ports, teardown, what it cannot prove) and NFCTimeSheets/NFCTimeSheetsUITests/WorkerRig*.swift. Nothing in the product changed (git diff d79dcd9 -- NFCTimeSheets/NFCTimeSheets NFCTimeSheets/NFCTimeSheets.xcodeproj server is empty; check-branding.mjs: all ok, no TODO line).

RIG: `export RIG_HOME=<abs dir outside the repo>; ops/ios-rig/up.sh` (25 s) -> throwaway Postgres 18 on 127.0.0.1:5433 (no unix socket; role rig_api NOSUPERUSER NOBYPASSRLS, so the real RLS runs), the 26 migrations, a seed (company 'Rig Reinigung GmbH', buildings Alpha/Beta, zones Stiege 1 verified / Keller UNVERIFIED / Dachboden deactivatable / Haupteingang verified, workers A and B, an operator, A's planned assignments), the REAL server.js bound to 127.0.0.1:8082 (serve.mjs strips SENTRY_/TWILIO_/RESEND_/GOOGLE_/ASC_ env by prefix), a TLS front on 127.0.0.1:8444 (throwaway CA + cert, JSONL wire log, fault injection), a CLONE of the iPhone 17 Pro simulator that trusts the CA, fresh single-use enrolment codes in $RIG_HOME/codes.env (0600). `ops/ios-rig/rig.sh build` builds the app with TS_API_HOST/TS_TAG_HOST=127.0.0.1:8444; `ops/ios-rig/walk.sh all|p1..p6|<walk>`; `ops/ios-rig/down.sh [--purge]`. The one constant that is NOT generated is the app's compiled-in X-App-Key (API.appKey, committed in cleartext): the product may not change, so serve.mjs is handed exactly that value from API.swift by environment; it is never written to disk.

RESULT of the full `walk.sh all` (19:01-19:37 CEST): 146 assertions PASS, 3 FAIL; the 3 are the same defect D1 (p6-waiting, bug-offline-manual-stop, bug-offline-switch). Per phase: signin 3/3, P2 (11 walks) all pass except none red (the 'pull' half of #8 is reported, not a red), P5 5 walks, P6 6 walks + device-wide, P3 8 walks, P4 15 walks, P1 5 walks. Teardown verified: no listener on 8082/8444/5433, no postgres/node rig process, no simulator clone, no *.pem/*.key/pgdata/secrets.env/codes.env under $RIG_HOME (logs, shots, results and DerivedData are kept until `down.sh --purge`).

FINDINGS (product, none fixed here)
D1 [real, payroll-relevant] Sync.swift:200-210 apply() is called from pushOpen (line 133) with the OPEN response and does `shift.autoClosed = wire.autoClosed` (204) and `shift.manualClose = wire.manualClose ?? shift.manualClose` (210). The open answer says false, so a LOCAL true set while the phone was offline is overwritten before pushClose reads it (164-165). Repro (walks bug-offline-manual-stop, bug-offline-switch): server unreachable; tap-start; then (a) 'Finish shift without a tag' -> the close goes out WITHOUT manual:true, server manual_close=false, corrected_at NULL; or (b) tap at ANOTHER building (walk-away) -> the old row goes out auto_closed:false, so decision-10's 'no shift reaches payroll with an unconfirmed end time' is bypassed. The online path is fine. Suggested fix (two lines, 'only upwards' as apply's own comment says): autoClosed = shift.autoClosed || wire.autoClosed; manualClose = shift.manualClose || (wire.manualClose ?? false). Android's Sync equivalent should be checked.
F2 Pull-to-refresh on the RUNNING screen starts refresh() (GET /roster, GET /flags) and then stops: no GET /shifts/open, no POST /shifts/open, in two runs; the 'Refresh' button under the clock (own unstructured Task) and pull-to-refresh on the IDLE list both deliver. Looks like the .refreshable task is cancelled after refreshRoster mutates the cache (try? turns the cancellations into silence). The worker has the Refresh button, so impact is low; but P2 #8's literal 'pull-to-refresh' fails on it.
O3 A deactivated zone drops out of the roster, so a row/shift started at it shows 'Unknown location' (running header, Recent) instead of the building.
O4 iOS close carries no location_uuid, so shifts.end_zone_id is NULL for every iOS close (Android records it).
O5 Killing the app in the FOREGROUND within ~10 s of signing in loses the session cookie (next launch: 401 -> 'Your session ended'); harness waits it out. Not reachable by a person.
O6 'No delivery attempt yet.' (TASK-365.7 #3) is unreachable on iOS: every written row has already been pushed once.

WHAT THE RIG CANNOT PROVE (criteria left open on purpose): the home-screen badge (never exposed by the Simulator icon, not drawn on the static grid), pending/delivered local notifications and the reminder ladder (no out-of-process reader), Live Activities, VoiceOver itself (labels are read from the accessibility tree), NFC and universal-link launch, a 9 h-old UNACKNOWLEDGED row ('overdue beats pending'). TASK-365.4 #1/#5/#6/#7, TASK-365.5 #14, TASK-365.6 #3/#5/#6/#7/#8, TASK-365.7 #3 and TASK-365.3 #8 stay open with the reasons in their notes.

Per-phase counts of that full run (replaces the loose sentence above): signin 1 walk 4/4; P2 10 walks 46/46; P5 5 walks 15/15; P6 6 walks 11 pass + 1 red (D1); P4 15 walks 26/26; P1 5 walks 19/19; defect probes 2 walks 0 pass + 2 red (D1, by design: they assert the correct behaviour); P3 8 walks 23/23. p2-online-verified was re-run afterwards with the 'Manual pill after a tag close' step added: 13/13.

D1 FIXED (2026-10-12): Sync.swift apply() now only raises autoClosed/manualClose (server answer OR local). Pinned by checks/sync-flags-check.swift (proven red under both mutations). Re-driven on the rig against the fixed build: bug-offline-manual-stop and bug-offline-switch PASS (4/4). Android twin tracked in TASK-369.
<!-- SECTION:NOTES:END -->
