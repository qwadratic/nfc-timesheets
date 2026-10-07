---
id: TASK-365.4
title: >-
  iOS P3: Shared phones: lists, tap toggle and out-of-app signals belong to the
  signed-in worker
status: In Progress
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-07 12:52'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.3
parent_task_id: TASK-365
priority: medium
ordinal: 288000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Worker B never sees or toggles worker A's rows, sign-out and a rejected session tear down the badge, reminders and Live Activity, and a direct worker change resets rendered state. Foreign rows are kept (device-wide outbox).
## Items (Android evidence at 60f6886)
### local-shifts-scoped-to-signed-in-worker - Local lists, open-shift lookup, tap toggle and signals are scoped to the signed-in worker  [PORT, size M, in_range]
- Android at 60f6886: ShiftStore.forWorker(id) feeds refresh()/reloadLocalLog(): Recent, History + totals, LogState.open, running screen, tab lock, manual pre-check/stop target, resolve reloads, material context. ShiftStore.openShift(workerId) is what a tap toggles, so B's tap never closes A's row; armSignals and BootReceiver see only that worker's open shift. adopt() of a DIFFERENT worker resets LogState (keeps pending summary) and schedule; async reads re-check the worker id before publishing. Foreign rows are never deleted: outbox and pending summary stay device-wide, SyncPlan blocks them (wrong_account), they reappear for their owner (driven A->B->A).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/data/ShiftStore.kt:136-148; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:588-598,627-646,705-713,752-758,829-835,863-868; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/Receivers.kt:57-58
- iOS gap: Every @Query/fetch over Shift is unscoped (no #Predicate in the app). On a shared phone B sees A's Recent/History and mixed totals and can swipe-delete A's rows; if A left a shift open B gets A's running screen, tab lock, reminders and material context, and B's first tap closes or auto-closes A's row (handleTap/manualStop take first(where: isOpen), read). Only pushOpen checks workerId; pushClose has no guard (read), so the close goes out under B's cookie and the server answers 404 unknown_shift.
- Port notes: Filter by worker.id at every read: init-built Query(filter: #Predicate<Shift> { $0.workerId == id }) for LogView, HistoryView (pass the worker from ContentView.swift:71), MaterialsView; compute shiftRunning inside the .eligible branch; predicate on currentRunning()'s FetchDescriptor so arm(for:) only sees the session worker; handleTap/manualStop use the scoped set. syncPending keeps iterating ALL rows; add a workerId guard to pushClose. Never delete foreign rows. Keep handleTap/outcome names and save-before-arm ordering. New source-text check (worker-scope-check.swift): no unfiltered Shift @Query, no unscoped first(where: isOpen), currentRunn

### worker-switch-resets-rendered-state - Changing the signed-in worker clears rendered shift state  [PARTIAL, size S, in_range]
- Android at 60f6886: adopt() of a different worker resets LogState and schedule; late async reads are dropped.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:560-598,627-630,705-713
- iOS gap: Mostly covered by SwiftUI teardown on sign-out. Not covered: a direct .eligible(A) -> .eligible(B) transition in Session.restore() keeps LogView's @State (unresolved list, switch notice) and does not re-run refresh.
- Port notes: Add .id(worker.id) to the TabView or key LogView's .task on worker.id.

### signals-torn-down-on-sign-out - Signing out or a rejected session tears down every out-of-app shift signal  [PORT, size S, pre_existing]
- Android at 60f6886: signOut() and dropToSignedOut() call ShiftSignals.arm(app, null): ongoing notification and all rung alarms cancelled; core-check asserts the signOut half. Predates the range.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:560-586,1052-1062; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/ShiftSignals.kt:84-89; android/checks/core-check.kt:2091-2097
- iOS gap: Session.signOut/serverRejectedSession clear cache, telemetry user and cookies only; arm(for:) is reachable only from LogView, unmounted by then. Badge, pending +1h..+8h reminders and Live Activity keep running on a signed-out, possibly handed-over phone.
- Port notes: Call ShiftSignalCenter.shared.arm(for: nil) from Session.clearLocalSession() (Auth.swift:176; both @MainActor) so both paths share one teardown. Re-arm on next sign-in already happens via LogView.task -> refresh(). Text assertion in shift-signal-check mirroring core-check.kt:2091-2097. Pair with worker scoping or the next worker's refresh re-arms from the leftover row.

## Files
Modify: NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/MaterialsView.swift, NFCTimeSheets/NFCTimeSheets/Auth.swift, NFCTimeSheets/checks/shift-signal-check.swift, NFCTimeSheets/checks/run.sh
Create: NFCTimeSheets/NFCTimeSheets/WorkerScope.swift, NFCTimeSheets/checks/worker-scope-check.swift
## Server contract
None new. Server attributes shifts to the session cookie (decision-22); close of another worker's client_uuid answers 404 unknown_shift (server/routes/app.js:317-321).

## Strings
None.

## Checks
- NEW worker-scope-check.swift (reads sources as text, like operator-gate-check): no unscoped open-shift read remains - every first(where: \.isOpen) / contains(where: \.isOpen) / .filter { !$0.isOpen } in ContentView.swift and MaterialsView.swift goes through the WorkerScope helper; the TabView carries .id(worker.id); Session.clearLocalSession contains ShiftSignalCenter.shared.arm(for: nil) (mirrors android/checks/core-check.kt:2091-2097)
- EXTEND shift-signal-check.swift: currentRunning() filters by worker id
- wire worker-scope-check into run.sh as an on-disk check (no cat)

## Design rules from the plan
- ONE helper in WorkerScope.swift: extension on Sequence<Shift> forWorker(_ id:) and openShift(for:), used by the lock (ContentView @Query at :30 has session.worker available), LogView open/recent/handleTap/manualStop/currentRunning, HistoryView (totals, list, swipe delete; pass worker into HistoryView() at ContentView.swift:71) and MaterialsView. The @Query stays unscoped on purpose: syncPending and the P6 delivery summary stay DEVICE-WIDE (Android keeps outbox and pending summary device-wide).
- Reset on worker change: .id(worker.id) as the first modifier on the TabView in ContentView.swift (recreates LogView/Materials/History/Settings state, covering Session.restore() replacing A with B without passing signedOut). Keep the existing .task(id: worker.id) materials.start.
- Sign-out teardown: one line in Session.clearLocalSession (Auth.swift:176-181) so signOut and the 401 path (serverRejectedSession) are both covered: ShiftSignalCenter.shared.arm(for: nil). Never from SignInView. Badge, +1h..+8h pending and delivered reminders, Live Activity all end.
- Never delete foreign rows. Do not touch pushOpen's wrong-account block or pushClose (same behaviour as Android; see openQuestions).
- Legacy workerId 0 rows stop being listed; DataMigrations/MigrationReceipt already archive most; accept.
- Manual-start guard (P2) and manualStop use the scoped open row.
- RISK: one missed read site leaves a cross-worker toggle; the text check exists for that.

## Verification matrix (drive it; do not assert from source)
Sign-out (+) | A signs in (real enrolment code on loopback server), tap-start, Settings > Sign out | sign-in screen; home-screen badge 0; no shift reminder pending/delivered | A's server shift still open; local row kept
Sign-in B (+) | B signs in | idle Log (no running screen), History tab present, Recent/History/totals empty of A's rows, Materials shows no 'For <A's building>' | -
B taps same place as A's open row (-) | DemoHooks tap at A's building | B gets ITS OWN running shift; A's row not closed, no switch card | server: new open row for B; A's row unchanged
B taps elsewhere (-) | tap another building | no flagged auto-close of A's row | A unchanged
Return of A (+) | B signs out, A signs in | A's running screen and signals (badge 1) return; tap closes A's row | server closes A's shift
Session rejected (-) | revoke session server-side mid-shift, trigger any request | drops to signed-out, badge 0, reminders gone
Worker replaced without signed-out (+) | cached A, /auth/session answers B | no A rows, unresolved list and switch notice reset
History (-) | swipe-delete as B | only B's rows removable
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Driven: Sign-out (+) | A signs in (real enrolment code on loopback server), tap-start, Settings > Sign out | sign-in screen; home-screen badge 0; no shift reminder pending/delivered | A's server shift still open; local row kept
- [ ] #2 Driven: Sign-in B (+) | B signs in | idle Log (no running screen), History tab present, Recent/History/totals empty of A's rows, Materials shows no 'For <A's building>' | -
- [ ] #3 Driven: B taps same place as A's open row (-) | DemoHooks tap at A's building | B gets ITS OWN running shift; A's row not closed, no switch card | server: new open row for B; A's row unchanged
- [ ] #4 Driven: B taps elsewhere (-) | tap another building | no flagged auto-close of A's row | A unchanged
- [ ] #5 Driven: Return of A (+) | B signs out, A signs in | A's running screen and signals (badge 1) return; tap closes A's row | server closes A's shift
- [ ] #6 Driven: Session rejected (-) | revoke session server-side mid-shift, trigger any request | drops to signed-out, badge 0, reminders gone
- [ ] #7 Driven: Worker replaced without signed-out (+) | cached A, /auth/session answers B | no A rows, unresolved list and switch notice reset
- [ ] #8 Driven: History (-) | swipe-delete as B | only B's rows removable
- [x] #9 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #10 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [x] #11 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [x] #12 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-07 implementation complete on branch ios-worker-parity (commit 8685b27). Status stays In Progress: criteria #1-#8 are DRIVEN walks that need a signed-in WORKER session against a server, and no rig provides one (decision-50 retired the Apple-token path; TASK-365.22 is that rig, not yet built). Nothing was driven and nothing is claimed as driven.

WHAT CHANGED
- WorkerScope.swift (new, Foundation-only): protocol WorkerScoped + Sequence extension forWorker(_:), openShift(for:) (the NEWEST open row of that worker), completed(for:), and WorkerScope.owns / isCurrent. Shift conforms in NFCTimeSheetsApp.swift (one-line extension).
- ContentView.swift: all three @Query over Shift are renamed allShifts (device-wide, loud on purpose) and read only through the helper: the tab lock (computed inside the .eligible branch), LogView open row / Recent / running screen / handleTap / manualStop / manual-start 'already open' guard / currentRunning() (what badge, ladder and Live Activity are armed from), History list + totals + swipe-delete (HistoryView(worker:)). TabView carries .id(worker.id) as its first modifier. Post-await re-arms (refresh(), handleTap's post-roster task, the scenePhase task) go through armIfStillCurrent(): arm only while session.worker?.id == worker.id.
- MaterialsView.swift: query renamed allShifts, openShift scoped (no 'For <A's building>' on B's request).
- Auth.swift: Session.clearLocalSession() ends with ShiftSignalCenter.shared.arm(for: nil), so signOut() and serverRejectedSession() (401) share one teardown. Rows untouched.
- Sync.swift: pushClose(_, end:, as:) skips (no error, no block, no request) a row another account queued. syncPending still iterates ALL rows. pushOpen's wrong-account block is untouched.
- Checks: NEW checks/worker-scope-check.swift (helper behaviour run for real + source-text assertions on ContentView/MaterialsView/Auth/Sync), EXTENDED checks/shift-signal-check.swift (currentRunning filters by worker id; clearLocalSession arms nil, mirroring android core-check.kt 2091-2097; post-await re-arm is the guarded one), wired into run.sh.

OPEN QUESTIONS DECIDED
(a) Legacy workerId 0 rows: HIDDEN from every list AND from every open-row lookup (WorkerScope.owns requires a session id > 0, so no id can ever match a 0). Safer: they belong to nobody, DataMigrations already archived most and MigrationReceipt showed the worker what happened once; the few it kept are blocked rows with no attributable owner, and a worker must not see them in History or be able to swipe-delete them. Cost: a kept-blocked legacy row is no longer visible in History (the archive file keeps it).
(b) Roster caches (Site rows, RosterZones) are NOT cleared on a worker change. GET /roster is worker-independent (server/routes/app.js roster(): every active location and zone, no worker predicate), so a colleague's cache leaks nothing, and one server = one company (a different company means a different API host, i.e. a different build). Clearing would cost an OFFLINE phone its building names, the manual-start picker (empty offline) and the same-building rule on the TAP path (a second door of the same building would read as a different building and auto-close the shift as a walk-away) - a cache miss is cosmetic, but this one would reach the tap. Android's signOut/adopt do not clear it either. worker-scope-check pins that clearLocalSession does not touch RosterZones/Site.
(c) The wrong-account sync-block persistence quirk is NOT fixed: pushOpen marks another account's UNSENT-OPEN row syncBlocked=true with 'different account' PERSISTENTLY (Android: SyncPlan Block + markFailed(blocked=true), same). So if A taps in/out offline, then B signs in and any sync pass runs, A's row stays blocked after A returns and is never delivered. FOLLOW-UP (not scheduled): on a wrong-account block, skip without persisting syncBlocked (or clear it when the owner signs back in) on BOTH platforms, and say so in P6's delivery summary.

DEVIATIONS FROM THE TASK TEXT
1. The task is self-contradictory on pushClose: Port notes say 'add a workerId guard to pushClose', Design rules say 'do not touch pushClose'. I added a SKIP-ONLY guard (no state change). Without it, A's finished-but-unsent close, pushed under B's cookie, answers 404 unknown_shift, which is terminal: A's row is blocked for ever and A's shift sits open on the server until the 8h timer. Android's SyncPlan does post it (and blocks); this is a deliberate improvement on Android parity, small and pinned by worker-scope-check. Revert is one line if the owner prefers strict parity.
2. run.sh wires worker-scope-check with `run ... WorkerScope.swift` (cat), not as a pure on-disk check, because the check also RUNS the helper's behaviour; its text half still reads the sources off disk like the others.
3. Added the post-await still-current-worker guard (armIfStillCurrent): Android re-checks the worker id before publishing async reads (TimeSheetViewModel.refresh); without it a refresh in flight at sign-out re-arms the badge the teardown just removed. The tap itself is never gated (the synchronous arm right after the local save is unchanged; worker-scope-check fails if anything between a tap and its save reads the session).

VERIFIED
- run.sh: all 20 checks green incl. worker-scope-check: OK, shift-signal-check: OK, manual-start-check: OK, zones-check: OK, localisation-check: OK (284 keys, all German) - no new strings (WorkerScope.swift has no String(localized:)/LocalizedStringKey and needs none).
- RED cases reproduced (mutate real file, auto-restore, harness in scratchpad red-p3.sh): RED1 handleTap toggles allShifts.first(where: \.isOpen); RED2 a new unscoped 'shifts' @Query in MaterialsView; RED3 History lists allShifts; RED4 TabView loses .id(worker.id); RED5 clearLocalSession without arm(for: nil) (BOTH checks fail); RED6 refresh() arms without the still-current guard (both fail); RED7 pushClose without the worker guard; RED8 currentRunning reads any worker's open row (both fail); RED9 History swipe-delete over allShifts; RED10 handleTap gains a session gate; RED11 helper lets legacy 0 match session 0; RED12 helper forWorker returns every row; RED13 sign-out wipes RosterZones. Baseline GREEN/GREEN, all files restored byte-for-byte.
- Extra evidence (throwaway, NOT committed, NOT a UI drive): WorkerScope compiled with the REAL Shift @Model and run against an in-memory SwiftData store: B has no open shift while only A's row is open; B's tap creates a new row; A's row stays open and untouched; nothing deleted.
- node ops/check-branding.mjs: all 14 lines ok, check-branding: OK, no TODO line printed.
- Debug and Release builds (generic iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED both, no warnings in the touched files. No edit to project.pbxproj or the entitlements.

NOT VERIFIED (criteria #1-#8 stay open): sign-out badge/reminders/Live Activity actually cleared on a device or simulator; B signing in on A's phone; B tapping A's building / elsewhere; A's return; a rejected session mid-shift; cached-A / server-B replace; History swipe as B. The .id(worker.id) reset and the stale-refresh guard are pinned as source text only; their runtime behaviour is unobserved.
<!-- SECTION:NOTES:END -->
