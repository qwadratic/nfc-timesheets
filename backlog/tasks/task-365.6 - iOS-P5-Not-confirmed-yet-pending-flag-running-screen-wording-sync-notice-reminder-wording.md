---
id: TASK-365.6
title: >-
  iOS P5: 'Not confirmed yet': pending flag, running-screen wording, sync
  notice, reminder wording
status: In Progress
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-07 13:46'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.5
parent_task_id: TASK-365
priority: medium
ordinal: 290000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A start that exists only on the phone says so in words (heading, state word, VoiceOver, one-line notice with Refresh) and in the reminder ladder; the wording flips when the server acknowledges. The clock keeps counting and no control is hidden.
## Items (Android evidence at 60f6886)
### running-shift-pending-flag - RunningShift carries a presentation-only pendingConfirmation flag  [PORT, size S, in_range]
- Android at 60f6886: RunningShift.pendingConfirmation (default false) is set to openSyncedAt == null at all three construction sites (armSignals, LogScreen, BootReceiver). ShiftSignal.plan is unchanged: lock, ladder timing and the 8h phase are identical for a pending shift.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/ShiftSignal.kt:129-142,167-184; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:655-669; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/Receivers.kt:61-70
- iOS gap: iOS RunningShift has four fields and no pending flag; asRunning ignores Shift.openSyncedAt.
- Port notes: Add 'let pendingConfirmation: Bool' (init default false) to RunningShift; set from shift.openSyncedAt == nil in LogView.asRunning. Leave plan() untouched. ShiftSignal.swift stays Foundation-only and must keep the three literals android/checks/core-check.kt:2155-2167 greps. Extend shift-signal-check: plan(pending) == plan(not pending); asRunning derives the flag from openSyncedAt.

### signals-rearm-after-push - Signals are re-armed after the tap's own push so pending wording flips on acceptance  [PARTIAL, size S, in_range]
- Android at 60f6886: handleTap arms after the local write, then refresh() pushes and ends in armSignals() again; also on foreground, manual start/stop, resolve.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:603-647,655-669,725-750
- iOS gap: handleTap arms once before the push; its Task and manualStop's Task never re-arm after await syncPending (read). Harmless today, but with pendingConfirmation the frozen ladder text stays 'pending' until the next foreground.
- Port notes: Add signals.arm(for: currentRunning()) after await syncPending in handleTap's Task and manualStop's Task. Must stay un-awaited (the check fails on 'await signals.') and the FIRST arm must still follow context.save(). Add a check line for the second arm.

### running-screen-pending-confirmation - Running screen distinguishes 'Not confirmed yet' (start only on the phone) from a server-accepted shift  [PORT, size M, in_range]
- Android at 60f6886: While the open row has openSyncedAt == null and the shift is not overdue: heading shift_pending_heading 'Noch nicht bestätigt' instead of 'Schicht läuft'; word under the clock shift_pending_label 'Lokal erfasste Zeit' instead of 'Läuft'; TalkBack a11y_shift_pending ('%d Stunden und %d Minuten für %s auf diesem Telefon erfasst. Noch nicht von der Verwaltung bestätigt.'). Timer keeps counting from the local start. Precedence overdue > pending > running; confirmed = !pending && syncError == null && !overdue. Queue/retry unchanged. A manual start is never pending on Android (adopted synced).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:936-945,1188-1227; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/ShiftSignal.kt:167-184; android/app/src/main/res/values/strings.xml:624-625,652
- iOS gap: ShiftScreen always says 'Clocked in' / 'Running' (VoiceOver 'Shift running for ...') the moment the local row exists, whether the server accepted, has not answered, or refused.
- Port notes: Needs running-shift-pending-flag. ShiftScreen: three-way heading, state word and accessibilityLabel with Android's precedence. New de+en keys: 'Not confirmed yet'/'Noch nicht bestätigt', 'Time recorded on this phone'/'Lokal erfasste Zeit', a11y key in non-positional form '%lld hours and %lld minutes recorded on this phone for %@. Not confirmed by the office yet.' Do NOT port shift_pending_body (dead). Simulator: add ShiftMockFlow cases where ShiftFlowAPI.open throws network / 422 zone_unverified / 422 unknown_location, driven with --ts-demo-tap. The error line and Refresh button are running-screen-sync-error-and-refresh (the five combined sou

### running-screen-sync-error-and-refresh - Running screen prints the open shift's delivery problem (or 'saved on this phone') and offers Aktualisieren  [PORT, size S, in_range]
- Android at 60f6886: When pendingConfirmation || syncError != null: a centred polite live-region line with the row's actual error sentence (zone not activated, location removed, no connection, ...) or worker_saved_locally 'Auf diesem Telefon gespeichert · noch nicht bestätigt', plus a text button log_refresh running refresh() (TimeSheetApp.kt:1228-1235, read). Also shown for an acknowledged shift carrying a sync error.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:945,1228-1235; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:602-647; android/app/src/main/res/values/strings.xml:629
- iOS gap: syncError/syncBlocked are rendered only by ShiftRow; the open row is excluded from Recent and History is hidden during a shift, so a queued or refused clock-in is invisible while the shift screen is up. No visible retry control there.
- Port notes: Pass the open Shift's syncError (already localized at Sync.swift:176) and syncBlocked plus an onRefresh closure into ShiftScreen; render under the clock (red icon when blocked) with a 'Refresh' button calling LogView.refresh. New de+en keys 'Saved on this phone · not yet confirmed', 'Refresh'/'Aktualisieren'. Add a rejection ShiftMockFlow.

### pending-confirmation-reminder-wording - Reminders (and Android's ongoing notification) say 'Not confirmed yet' while the start is unacknowledged  [PORT, size S, in_range]
- Android at 60f6886: While pending: ongoing notification title notify_pending_title 'Noch nicht bestätigt: %s' and body notify_pending_body 'Die Zeit ist auf dem Telefon gespeichert. Öffnen Sie die App und prüfen Sie den Hinweis.' (precedence pending > overdue > running). Each +1h..+8h alarm carries the flag as an extra; postReminder uses the pending title/body for EVERY rung including the 8h auto-close one (ShiftSignals.kt:250-261, read). Re-arm rewrites the extra; BootReceiver passes it.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/ShiftSignals.kt:63,91-148,197-212,231-268; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/Receivers.kt:16-25,57-70; android/app/src/main/res/values/strings.xml:627-628
- iOS gap: scheduleLadder has only two wordings ('Still clocked in' + '<n> h at <place>...' and the 8h auto-close pair); a never-accepted shift is reminded as normal and at 8h claims it was closed automatically.
- Port notes: Needs running-shift-pending-flag and signals-rearm-after-push (iOS freezes content at schedule time). In scheduleLadder add a FIRST branch on running.pendingConfirmation, before isAutoCloseWarning. New de+en keys 'Not confirmed yet: %@' and 'Your time is saved on this phone. Open the app and check the message.' Text assertion in shift-signal-check that the pending branch precedes auto-close.

## Files
Modify: NFCTimeSheets/NFCTimeSheets/ShiftSignal.swift, NFCTimeSheets/NFCTimeSheets/ShiftSignalCenter.swift, NFCTimeSheets/NFCTimeSheets/ShiftScreen.swift, NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/Localizable.xcstrings, NFCTimeSheets/checks/shift-signal-check.swift
Create: NFCTimeSheets/NFCTimeSheets/PendingNotice.swift
## Server contract
None. Reads Shift.openSyncedAt/syncError/syncBlocked written by Sync.swift.

## Strings
English keys: 'Not confirmed yet' (shift_pending_heading), 'Time recorded on this phone' (shift_pending_label), '%lld hours and %lld minutes recorded on this phone for %@. Not confirmed by the office yet.' (a11y_shift_pending, German positional %1$lld %2$lld %3$@ in the de value only), 'Saved on this phone · not yet confirmed' (worker_saved_locally), 'Refresh' (log_refresh; key does NOT exist today), 'Not confirmed yet: %@' (notify_pending_title), 'Your time is saved on this phone. Open the app and check the message.' (notify_pending_body). German from Android values/strings.xml.

## Checks
- EXTEND shift-signal-check.swift: plan(pending) == plan(not pending) (lock, ladder, 8h phase identical); asRunning derives pendingConfirmation from openSyncedAt == nil; presentation precedence overdue > pending > running; grace logic (see decisions); ladder kind per rung is pending for EVERY rung incl. the 8h one when pending; handleTap and manualStop re-arm after syncPending as an un-awaited signals.arm, first arm still after context.save() and no 'await signals.'
- ShiftSignal.swift keeps the three literals android/checks/core-check.kt:2155-2167 greps (autoCloseAfter, reminderHours, visibleTabs); run the Android check if that file text changes
- localisation-check.swift green

## Design rules from the plan
- RunningShift gains 'let pendingConfirmation: Bool' with init default false (existing RunningShift(...) calls in shift-signal-check.swift:37-39 keep compiling); LogView.asRunning sets it from shift.openSyncedAt == nil. ShiftSignal.plan() is NOT changed. Update the RunningShift doc: presentation only.
- Foundation-only presentation function in ShiftSignal.swift: presentation(of:now:graceElapsed:hasSyncError:) -> overdue | pending | running. iOS writes the row BEFORE the POST (unlike Android), so every online tap is unacknowledged for one request: ShiftScreen holds @State graceElapsed set by .task(id: running.pendingConfirmation) after a 2 s sleep, true at once when the start is older than 10 s or a sync error exists. Deliberate deviation; documented in the check. confirmed = !pending && no syncError && !overdue (used by P7).
- ShiftScreen: three-way heading ('Over 8 hours' / 'Not confirmed yet' / 'Clocked in'), state word under the clock ('This shift passed...' / 'Time recorded on this phone' / 'Running'), accessibilityLabel branch. The Text(timerInterval:) clock is untouched. TRAP: the notice line and its Refresh button are a SEPARATE view placed after clock(...) in the VStack; inside the clock card they would be swallowed by accessibilityElement(children: .ignore).
- PendingNotice (own file, no surface styling): shows when presentation == pending or the open row has a syncError: the row's already-localized syncError (Sync.swift:176) with a red icon when syncBlocked, else 'Saved on this phone · not yet confirmed', plus a bordered 'Refresh' button calling LogView.refresh. Polite live region. ShiftScreen gains parameters syncError, syncBlocked, onRefresh. Never add a path that deletes a blocked row (TASK-362).
- Reminders: scheduleLadder (ShiftSignalCenter.swift:109-145) branches on running.pendingConfirmation for EVERY rung (Android ShiftSignals.kt:250-261): title 'Not confirmed yet: <place>', body pending text. Because iOS freezes text at schedule time, re-arm after the ack: add signals.arm(for: currentRunning()) AFTER await syncPending in BOTH handleTap's trailing Task (ContentView.swift:660-671) and manualStop's Task (:499) - un-awaited, FIRST arm stays after context.save(). refresh() already re-arms (:556).
- Do NOT port shift_pending_body (dead). LiveActivity untouched (notPorting).
- RISK: editing ShiftSignal.swift text can fail the ANDROID CI job; RunningShift is Equatable and feeds arm(for:) so the flip re-arms once per shift.

## Verification matrix (drive it; do not assert from source)
Running, online (+) | tap-start against loopback server | heading 'Clocked in' / 'Running'; 'Not confirmed yet' never flashes (2 s grace) | row openSyncedAt set, server open row
Running, server unreachable (-) | stop server, tap-start | after ~2 s heading 'Not confirmed yet', word 'Time recorded on this phone', notice 'No connection - will send when you're back online.' + Refresh; clock keeps counting; Stop/Scan/tabs all usable | no server row
Recovery (+) | start server, press Refresh | heading flips to 'Clocked in', notice disappears, ladder re-armed with normal wording | server open row
Refusal (-) | zone_unverified / unknown_location tap | notice shows the row's sentence (red icon when blocked), heading 'Not confirmed yet' | 422
Overdue (+) | shift past 8h | overdue wording wins over pending
VoiceOver | focus the clock and the notice | label 'N hours M minutes recorded on this phone for B. Not confirmed...'; Refresh is a separate focusable button
Reminders | pending shift: inspect scheduled request text (print in DEBUG or checks) | every rung 'Not confirmed yet: B'; after ack re-armed to 'Still clocked in' wording
Manual stop (+) | Finish without a tag then ack | re-arm happens after the push, ladder cleared
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Driven: Running, online (+) | tap-start against loopback server | heading 'Clocked in' / 'Running'; 'Not confirmed yet' never flashes (2 s grace) | row openSyncedAt set, server open row
- [ ] #2 Driven: Running, server unreachable (-) | stop server, tap-start | after ~2 s heading 'Not confirmed yet', word 'Time recorded on this phone', notice 'No connection - will send when you're back online.' + Refresh; clock keeps counting; Stop/Scan/tabs all usable | no server row
- [ ] #3 Driven: Recovery (+) | start server, press Refresh | heading flips to 'Clocked in', notice disappears, ladder re-armed with normal wording | server open row
- [ ] #4 Driven: Refusal (-) | zone_unverified / unknown_location tap | notice shows the row's sentence (red icon when blocked), heading 'Not confirmed yet' | 422
- [ ] #5 Driven: Overdue (+) | shift past 8h | overdue wording wins over pending
- [ ] #6 Driven: VoiceOver | focus the clock and the notice | label 'N hours M minutes recorded on this phone for B. Not confirmed...'; Refresh is a separate focusable button
- [ ] #7 Driven: Reminders | pending shift: inspect scheduled request text (print in DEBUG or checks) | every rung 'Not confirmed yet: B'; after ack re-armed to 'Still clocked in' wording
- [ ] #8 Driven: Manual stop (+) | Finish without a tag then ack | re-arm happens after the push, ladder cleared
- [x] #9 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #10 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [x] #11 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [x] #12 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-07 iOS P5 implementation complete on branch ios-worker-parity (code commit e46092e, "ios: \"Not confirmed yet\" - a start only the phone knows about says so ... (P5)"). Status stays In Progress: criteria #1-#8 are DRIVEN walks that need a signed-in WORKER session against a server, and no rig provides one (decision-50 retired the Apple-token path; TASK-365.22 is that rig, not yet built). Nothing was driven and nothing is claimed as driven. Criteria #9, #10, #11, #12 are met and ticked. No new decision (the plan has none for this package).

WHAT CHANGED
- ShiftSignal.swift (still Foundation-only, the three literals android/checks/core-check.kt greps untouched): RunningShift.pendingConfirmation (init default false; doc says presentation only); ShiftPresentation {overdue, pending, running}; ShiftSignal.isPending / presentation(of:now:graceElapsed:hasSyncError:) (overdue > pending > running) / isConfirmed (Android's confirmed, read off the FLAG so the grace never makes an unacknowledged start confirmed; for P7); ReminderKind {pending, autoClose, nudge}, reminderKind(hour:pendingConfirmation:) (pending FIRST, for every rung incl. 8h), Rung and ladder(for:now:) (the rungs as a pure value, so pending vs confirmed is provable at fixed instants). plan() is untouched and a check asserts its body never mentions pending.
- PendingNotice.swift (new, Foundation-only, needs ShiftSignal.swift cat-ed in): grace = 2 s, staleAfter = 10 s, graceElapsedAtOnce(startedAt:now:hasSyncError:), PendingNotice.Content {savedLocally, problem(String, blocked:)}, content(pending:syncError:syncBlocked:) and content(for:graceElapsed:syncError:syncBlocked:).
- PendingNoticeView.swift (new, SwiftUI, no surface of its own, red only for a blocked row's icon): the line (Text(verbatim:) for the row's already-localised sentence, String(localized:) for "Saved on this phone · not yet confirmed"), a bordered Refresh button, low-priority AccessibilityNotification.Announcement on appear / text change (Android's polite live region).
- ShiftScreen.swift: params syncError, syncBlocked, onRefresh (declared BEFORE schedule/onReloadSchedule so P4's call-site pin still holds); @State graceElapsed + .task(id: GraceKey(startTime, pending)) sleeping PendingNotice.grace; headingText / stateWord / spokenState = the three words as small functions of the presentation (a reskin restyles header()/clock() and keeps them); clock() draws the same ticking digits for pending as for running; PendingNoticeView sits after the clock card, before the tap instruction.
- ShiftSignalCenter.swift: scheduleLadder iterates ShiftSignal.ladder and switches on rung.kind (.pending first): title "Not confirmed yet: <place>", body "Your time is saved on this phone. Open the app and check the message." for every rung.
- ContentView.swift: asRunning sets pendingConfirmation from shift.openSyncedAt == nil (the only RunningShift construction site); ShiftScreen gets openRow?.syncError, syncBlocked, onRefresh: { Task { await refresh() } }; handleTap's trailing Task and manualStop's Task call armIfStillCurrent() right after await syncPending (un-awaited; the first arm still follows context.save()).
- Localizable.xcstrings: 7 keys, German read OUT of android strings.xml by script (scratchpad/p5/catalog-patch-p5.js). The compiler's own .stringsdata for ShiftScreen / PendingNoticeView / ShiftSignalCenter lists exactly these keys and all are in the catalogue; the built de.lproj holds the German.
- checks: shift-signal-check.swift extended (section 7); pending-notice-check.swift new, wired into run.sh.

DECISIONS TAKEN WHERE THE TASK LEFT A QUESTION
1. The notice follows Android's rule (flag with the grace over, OR a sync error), NOT the overdue precedence the heading uses: an unacknowledged start older than 8 h keeps its notice and Refresh under "Over 8 hours". The task text said "presentation == pending"; Android's condition is `pendingConfirmation || syncError != null`. Pinned.
2. NO new ShiftMockFlow cases (the task's port notes asked for network / zone_unverified / unknown_location flows): the owner's scope rule (no new mocks) and the run brief forbid it, and without a worker session nothing could drive them anyway. The real routes are stopping the staging/loopback server (offline) and a real 422 from the server; P4 declined its mock the same way. The Driven criteria stay open for TASK-365.22.
3. The Live Activity is NOT told (task: notPorting). ShiftActivityAttributes.ContentState stays {overdue}; pending-notice-check pins it and that LiveActivityController never mentions pending. No widget extension target exists (owner-only).
4. The re-arm after the push uses armIfStillCurrent() (P3's session-guarded arm), not a bare signals.arm: a sign-out while the push is in flight must not be undone. Same for manualStop (it arms nothing - the shift is closed - but the rule "every push is followed by one arm" is uniform and pinned).
5. A manual start is NOT pending on Android (adopted synced); on iOS handleTap(manual: true) writes the row before the sync pass like any tap, so it is unacknowledged for one request and the 2 s grace covers it. openSyncedAt is deliberately not pre-set (the sync pass must still apply the server's row).
6. The grace's .task id carries the start time too, so a switch to another building (flag stays true) gets a fresh grace.
7. Refresh is not debounced and shows no progress (Android's is the same); concurrent refreshes are already possible via pull-to-refresh and the push is idempotent (200 duplicate on the same client_uuid).
8. shift_pending_body is not ported (dead on Android); pending-notice-check asserts it is absent.

VERIFIED
- NFCTimeSheets/checks/run.sh: every check green, incl. "shift-signal-check: OK", "pending-notice-check: OK", "schedule-check: OK" (P4's text pins untouched and still holding), "localisation-check: OK (305 keys, all German)" (298 + 7), "checks: OK".
- node ops/check-branding.mjs: 14 lines, all "ok", "check-branding: OK"; no TODO line and no non-ok line printed on this branch.
- Debug and Release builds (generic/platform=iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED both; the only warnings are the two pre-existing ones (MaterialStore.swift:54, WriteGuard.swift:122). PendingNotice.o and PendingNoticeView.o are in both targets (file-system-synchronized group, no pbxproj edit); the Release binary contains neither debug marker. No edit to project.pbxproj or NFCTimeSheets.entitlements.
- RED cases reproduced (scratchpad/red-p5.sh mutates the real files in place and restores them byte-for-byte; all restored). 58 cases, every one RED in its target check, baseline GREEN in all four checks it runs. First FAIL line per group: plan gated by the flag (reminders / badge / lock) -> "a pending shift has the SAME plan as a confirmed one ... the flag chooses words, it never gates the lock, the badge, the ladder or the Live Activity"; isPending ignores the grace -> "THE GRACE: a start the server has not answered yet is NOT called 'Not confirmed yet' straight away"; ignores the error -> "a sync error ends the grace at once"; pending beats overdue -> "OVERDUE BEATS PENDING at exactly 8h"; confirmed ignores the flag / the error -> "an unacknowledged start is never confirmed" / "a row carrying a sync error is not confirmed"; 8h rung says auto-close while pending -> "EVERY rung of a pending shift says 'Not confirmed yet' ... including the 8h one"; pending loses a rung -> "pending and confirmed have the same rungs at the same delays"; pending case after auto-close in scheduleLadder -> "the PENDING wording is the FIRST branch of the ladder"; ladder decides itself again -> "scheduleLadder takes its rungs, their kinds and their delays from ShiftSignal.ladder"; pending body claims an auto-close -> "the pending rung is 'Not confirmed yet: <place>' with the saved-on-this-phone body"; flag from isFullySynced / forgotten -> "asRunning sets pendingConfirmation from shift.openSyncedAt == nil"; no re-arm after the push / re-arm before it (handleTap and manualStop) -> "RE-ARMS after `await syncPending`"; awaited signal -> "no signal call is awaited on the tap path"; second direct arm -> "the FIRST arm ... is still the only direct signals.arm( in handleTap"; arm before save -> "THE LOCAL ROW IS SAVED BEFORE ANY SIGNAL WORK"; Android's literal reworded -> "ShiftSignal.swift still contains 'autoCloseAfter: TimeInterval = 8 * 3600'"; SwiftUI import -> "ShiftSignal.swift is still Foundation-only"; grace constants / no grace / error not ending it / old start waiting -> the grace assertions; generic line over the row's sentence, empty error drawn, notice ignoring the grace, blocked dropped, notice yielding to overdue -> the content assertions; notice after the instruction -> "running screen order"; notice inside clock() -> "THE TRAP"; Scan hidden / Finish disabled -> "the running stack has exactly four conditionals" / "ShiftScreen disables and hides nothing"; pending drawn as overdue -> "everything that is not overdue - pending included - draws the system-ticked clock"; heading order / literal / word / spoken label wrong; uncancelled grace sleep; grace ignored; empty Refresh closure; surface / red text / red icon for every problem / no announcement / disabled button / Text(text) in the notice view; Live Activity ContentState gaining pending; German of Refresh wrong; reminder-title key removed or typed positionally; spoken-label German losing a sentence or gaining a placeholder; a schedule read in manualStop (P4's pin) -> each its own assertion. Where localisation-check stayed GREEN (wrong-but-valid German, a missing key for a String(localized:) literal, a dropped sentence) the new pending-notice-check is what turned RED: localisation-check's extractor only sees Text(" / Button(" literals and cannot compare to Android.
- Extra evidence, throwaway and NOT committed, NOT a driven walk and not on iOS: PendingNoticeView compiled into a macOS script and drawn with ImageRenderer from injected data (the offline sentence, a refused row with the red icon, the generic line): wrapping, centring, the red icon and the bordered Refresh button read correctly at 330 pt.

NOT VERIFIED (criteria #1-#8 stay open): that an online tap never flashes "Not confirmed yet" (the 2 s grace is a unit-proven rule plus a text-pinned wiring, not seen); that a stopped server / a real 422 shows heading, word, notice and red icon as designed; that Refresh flips the heading and the ladder; that a state read inside the TimelineView closure (@State graceElapsed) re-renders at 2 s (expected, not seen); VoiceOver order and the separate Refresh focus; that the announcement is spoken; that the re-armed ladder's text is what iOS shows (the pending-request text was not inspected on a device); the manual-stop walk. The Android check (android/checks/run.sh) was NOT run: it downloads org.json from Maven Central on first use; its only read of an iOS file is ShiftSignal.swift's three literals, which shift-signal-check re-asserts.

RESKIN COLLISIONS (B1-B5 must touch these): (1) ShiftScreen.header()/clock() now take `presentation:` and call headingText / stateWord / spokenState; B3 keeps those three and restyles where they are drawn. (2) PendingNoticeView is bare on the blue field (default .primary text, system .bordered button, system .red for a refused row): B3's on-blue ink and B1's tokens decide its colours; it has no `ink` parameter yet. (3) pending-notice-check pins the CURRENT structure as text: the stack order header < clock < notice < instruction < Scan < Finish, exactly four `if` lines in the stack, `if presentation == .overdue {` / `} else {` in clock(), ShiftScreen reading the flag in exactly two places, the call-site argument order in ContentView (syncError, syncBlocked, onRefresh before schedule), the notice view having no surface; a reskin that moves things updates those assertions in the same commit. (4) P4's schedule-check pins still hold (scheduleCard before helpCard, exactly eight "schedule" lines in ContentView.swift: do not write that word in a ContentView code line). (5) P6 (confirmation motion) reads ShiftSignal.isConfirmed; P7 (delivery) reuses the same syncError / syncBlocked / refresh and the grace if it shows a pending line.
<!-- SECTION:NOTES:END -->
