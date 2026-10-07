---
id: TASK-365.4
title: >-
  iOS P3: Shared phones: lists, tap toggle and out-of-app signals belong to the
  signed-in worker
status: To Do
assignee: []
created_date: '2026-10-07 12:21'
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
- [ ] #9 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #10 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [ ] #11 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [ ] #12 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
