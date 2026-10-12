---
id: TASK-365.7
title: 'iOS P6: Delivery status: count rows, details sheet, sign-in screen'
status: In Progress
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-12 10:43'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.6
parent_task_id: TASK-365
priority: medium
ordinal: 291000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Unsent and blocked shifts stay visible as compact tappable count rows on the idle list, the running screen and the sign-in screen, opening a details sheet with a state-specific explanation, the earliest start and the last attempt. Never promises automatic delivery (iOS has no background delivery).
## Decision to record FIRST (decision-79)
Record decision-79: iOS says what the phone still holds and what the server has not confirmed - in words, never promising automatic delivery?
Context: Android TASK-339/363 added 'Not confirmed yet' running state and reminder wording, and count rows plus a details sheet for unsent/blocked shifts, with AC3 'no false automatic-delivery promise'. iOS differs by platform: no background delivery (Sync.swift:68-73), the shift is written BEFORE the POST, and there is no per-row last-attempt field. Proposed rule: (1) presentation only - the pending state never stops the clock, hides a control, or changes ShiftSignal.plan; (2) a start unacknowledged for >2 s, or carrying an error, reads 'Not confirmed yet' on screen, VoiceOver and every reminder rung; (3) unsent/blocked counts are DEVICE-WIDE, blocked and waiting are separate rows, and every sentenc
Recommendation (planned as accepted): Accept as written. The Android wording would be a false promise on iOS and a SwiftData column risks the unpushed-shift store. Planned as accepted.

## Items (Android evidence at 60f6886)
### delivery-status-rows - Unsent and blocked shifts stay visible as compact count rows on idle and running screens  [PORT, size M, pre_existing]
- Android at 60f6886: DeliveryStatus renders nothing when PendingWork.Summary is empty; otherwise up to two tappable min-56dp rows with glyph + chevron: plural delivery_blocked_short ('%d Schicht braucht / Schichten brauchen die Verwaltung') and delivery_waiting_short ('%d Schicht(en) noch auf diesem Telefon'); each opens the details sheet. Shown under the idle start card and on the running screen (on-field ink). Summary is device-wide (ShiftStore.pendingSummary over queue() = all rows, read): waiting = not fully synced and not blocked, blocked = terminal refusal/wrong account; an open shift whose OPEN landed is not pending. Replaced the pre-range PendingCard.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/DeliveryStatus.kt:29-47,85-106; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1020-1022,1254; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/PendingWork.kt:45-81
- iOS gap: iOS has no summary of unsent work on any screen (only per-row labels in Recent/History, invisible while a shift runs) and never had Android's PendingCard.
- Port notes: Foundation-only PendingWork.swift (waiting, blocked, oldestStart; same predicate as syncPending) with checks/pending-work-check.swift; one DeliveryStatusRows view in LogView.idleList and ShiftScreen fed by an UNSCOPED fetch. Plural variations (one/other) in de AND en for '%lld shifts need your office' and '%lld shifts still on this phone'; add both to the plural guard at localisation-check.swift:135-138. Simulator: ShiftMockFlows that throw network and unknown_location.

### delivery-details-sheet - Delivery details sheet with state-specific explanation, earliest start and last attempt  [PORT, size M, pre_existing]
- Android at 60f6886: Tapping a row opens a bottom sheet 'Übertragung': blocked count (error colour) + delivery_blocked_detail (office must review; stays on phone; no automatic retry; tell the office the time below); waiting count + exactly one sentence: signedOut -> delivery_sign_in, !armed -> delivery_not_scheduled, else delivery_automatic; then the force-stop note; divider; pending_oldest (reworded in range to 'Frühester Schichtbeginn: %s'); 'Zuletzt versucht: %s' or 'Noch kein Übertragungsversuch.'; Dismiss. Closing deletes nothing.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/DeliveryStatus.kt:48-83; android/app/src/main/res/values/strings.xml:169,653-658; android/app/src/main/res/values-en/strings.xml:117,524-529
- iOS gap: No details surface; Shift has no last-attempt time; iOS has no background delivery.
- Port notes: .sheet with detents from the rows. Waiting text on iOS: the 'not active - open the app with an internet connection' sentence when signed in, the sign-in sentence when signed out; do NOT port delivery_automatic or the force-stop note. Last attempt needs 'lastAttemptAt: Date?' on Shift stamped in pushOpen/pushClose, or omit the line. New de+en keys: Delivery/Übertragung, blocked detail, two waiting sentences, 'Earliest shift start: %@', 'Last attempt: %@', 'No delivery attempt yet.'

### delivery-status-on-sign-in - Sign-in screen shows shifts still held on the phone  [PORT, size S, pre_existing]
- Android at 60f6886: restoreSession/signOut keep LogState.pending; SignInScreen renders DeliveryStatus(pending, signedOut = true) under the intro; sheet sentence 'Melden Sie sich mit demselben Konto an, damit diese Einträge übertragen werden können.'
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:182-187,254; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:373-380,568-579; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/DeliveryStatus.kt:62-69
- iOS gap: SignInView says nothing about unsent rows; only a Settings footer read before signing out.
- Port notes: After delivery-status-rows: SignInView gets an unfiltered @Query over Shift and a Section between the brand block and CodeSignInSection with signedOut wording.

## Files
Modify: NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/ShiftScreen.swift, NFCTimeSheets/NFCTimeSheets/Sync.swift, NFCTimeSheets/NFCTimeSheets/Localizable.xcstrings, NFCTimeSheets/checks/run.sh
Create: NFCTimeSheets/NFCTimeSheets/PendingWork.swift, NFCTimeSheets/NFCTimeSheets/DeliveryStatusViews.swift, NFCTimeSheets/checks/pending-work-check.swift
## Server contract
None. Local summary over every Shift row on the device.

## Strings
English keys: 'Delivery' (delivery_title), plural '%lld shifts need your office' (delivery_blocked_short), plural '%lld shifts still on this phone' (delivery_waiting_short) - both as de AND en plural variations (precedent Localizable.xcstrings:118-157), delivery_blocked_detail, delivery_sign_in, delivery_not_scheduled, 'Earliest shift start: %@' (pending_oldest), 'Last attempt: %@' (pending_last_try), 'No delivery attempt yet.' (delivery_no_attempt), 'Close' (from P4). German from Android values/strings.xml.

## Checks
- NEW pending-work-check.swift (cat PendingWork): summarise mirrored from android/checks/core-check.kt:2617-2710 - empty queue = nothing; a not-yet-opened row waits; an open shift whose OPEN landed is NOT pending; a closed fully-synced row is not pending; open synced but close unsent waits; blocked counted separately and never folded into waiting; oldest start spans waiting+blocked; total == number of rows touched; uses the same isFullySynced predicate as Sync.swift
- wire pending-work-check into run.sh; localisation-check.swift green including plural variations

## Design rules from the plan
- OD3 (decision-79 proposal) governs wording; planned as accepted.
- PendingWork.summarise(_ rows:[PendingRow], lastAttemptAt: Date?) is Foundation-only; PendingRow {startTime, openSyncedAt, closeSyncedAt, isOpen, syncBlocked} is mapped from Shift in the view layer. waiting = not fully synced and not blocked; blocked = terminal refusal or wrong account. DEVICE-WIDE: fed the unscoped @Query (P3 kept it unscoped on purpose).
- Last attempt WITHOUT a SwiftData schema change: a single UserDefaults date stamped in syncPending immediately BEFORE each push attempt on a not-fully-synced, non-blocked row (Android markAttempted-before-call, ShiftSync.kt). Rejected alternative: Shift.lastAttemptAt - a failed lightweight migration is a fatalError at launch (NFCTimeSheetsApp.swift:111) for a line of text. Document the deviation (global vs per-row max) in the check header.
- iOS wording differs from Android: waiting sentence is 'Automatic delivery is not currently active. Open the app with an internet connection to try delivery again.' (delivery_not_scheduled) when signed in, delivery_sign_in when signed out; do NOT port delivery_automatic (false promise, TASK-363 AC3, Sync.swift:68-73 'no background retry'), pending_force_stop_note or the pushArmed input.
- Views are self-contained and unstyled: DeliveryStatusRows (up to two min-44pt tappable bordered rows with glyph + chevron, blocked first, error styling for blocked) and DeliveryDetailsSheet (.sheet with .medium/.large detents: blocked count + delivery_blocked_detail, waiting count + exactly one sentence, divider, 'Earliest shift start: %@', 'Last attempt: %@' or 'No delivery attempt yet.', Close). Closing deletes nothing. The blocked detail must give the worker the time to tell the office.
- Placement: idle list Section right after the unresolved banner (above schedule and Recent); ShiftScreen after the resolver card; SignInView Section between the brand block and CodeSignInSection with signedOut: true and its own sheet (SignInView has no LogView).
- RISK: counts must use the same fully-synced predicate as the push; 'Sent'/'Sending…' labels in ShiftRow stay as they are.

## Verification matrix (drive it; do not assert from source)
Idle, empty queue (+) | nothing sent unsent | no rows, no sheet
Waiting (+) | tap-start then Stop with server down | idle shows '1 shift still on this phone' row; tap opens sheet: count, 'Automatic delivery is not currently active...', earliest start, 'No delivery attempt yet.' | no server rows
Attempted (+) | pull-to-refresh with server still down | sheet shows 'Last attempt: <time>' | -
Recovery (+) | start server, pull-to-refresh | row disappears | server has both halves
Blocked (-) | zone_unverified-turned-removed / unknown_location row | red '1 shift needs your office' row; sheet detail names earliest start; waiting+blocked shows two rows | 422
Running screen (+) | open shift acked | no row for it; a previous closed-unsent row DOES show
Sign-in (+) | sign out with unsent rows | SignInView shows the rows and sheet says 'Sign in with the same account...', never 'open the app' | -
Wording (-) | read every state | never says 'automatically' or force-stop
Device-wide (-) | A's unsent row, B signed in | B's counts include it (blocked wrong account); lists do not
Dynamic Type 200% | rows wrap, stay >= 44pt
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 decision-79 recorded (backlog decision create) BEFORE the code, and listed in the epic
- [ ] #2 Driven: Idle, empty queue (+) | nothing sent unsent | no rows, no sheet
- [ ] #3 Driven: Waiting (+) | tap-start then Stop with server down | idle shows '1 shift still on this phone' row; tap opens sheet: count, 'Automatic delivery is not currently active...', earliest start, 'No delivery attempt yet.' | no server rows
- [ ] #4 Driven: Attempted (+) | pull-to-refresh with server still down | sheet shows 'Last attempt: <time>' | -
- [ ] #5 Driven: Recovery (+) | start server, pull-to-refresh | row disappears | server has both halves
- [ ] #6 Driven: Blocked (-) | zone_unverified-turned-removed / unknown_location row | red '1 shift needs your office' row; sheet detail names earliest start; waiting+blocked shows two rows | 422
- [ ] #7 Driven: Running screen (+) | open shift acked | no row for it; a previous closed-unsent row DOES show
- [ ] #8 Driven: Sign-in (+) | sign out with unsent rows | SignInView shows the rows and sheet says 'Sign in with the same account...', never 'open the app' | -
- [ ] #9 Driven: Wording (-) | read every state | never says 'automatically' or force-stop
- [ ] #10 Driven: Device-wide (-) | A's unsent row, B signed in | B's counts include it (blocked wrong account); lists do not
- [ ] #11 Driven: Dynamic Type 200% | rows wrap, stay >= 44pt
- [x] #12 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #13 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [x] #14 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [x] #15 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision number: the plan called this decision-78/79/80, but 77 and 78 are taken by branch admin-declutter and 79 is manual start. Record it with backlog decision create (next free number) BEFORE the code.

2026-10-12 iOS P6 implementation complete on branch ios-worker-parity (code commit c73f54c, "ios: delivery status - count rows, details sheet and the sign-in screen say what the phone still holds (P6, decision-82)"). Status stays In Progress: criteria #2-#11 are DRIVEN walks that need a signed-in WORKER session against a server, and no rig provides one (decision-50 retired the Apple-token path; TASK-365.22 is that rig, not yet built). Nothing in the matrix was driven against the app and nothing is claimed as driven. Criteria #1, #12, #13, #14, #15 are met and ticked.

DECISION: recorded as decision-82 BEFORE any code (backlog decision create, status accepted; this task's text calls it decision-79 / OD3 - 79 is the agent-integration decision on main, 81 is manual start). AGENTS.md checklist has the pointer line; the epic's notes list it.

WHAT CHANGED
- PendingWork.swift (new, Foundation-only): PendingRow {startTime, openSyncedAt, closeSyncedAt, isOpen, syncBlocked + finishOwed (Shift.pendingEvidenceEnd != nil), queuedByAnotherAccount, lastChangedAt}; PendingWork.state(of:) = THE predicate (delivered / waiting / blocked); summarise(_:lastAttemptAt:) -> {waiting, blocked, waitingForOthers, oldestStart, lastAttemptAt}; waitingSentence(for:signedOut:) (signIn | notActive | nil); the 2 s in-flight grace (isInFlight / settled / nextSettle); DeliveryAttempt (one UserDefaults date, stamp(at:in:), date(seconds:), last(in:)).
- Sync.swift: syncPending iterates exactly `PendingWork.state(of: shift.deliveryRow()) == .waiting` - the old inline `!syncBlocked && (!isFullySynced || pendingEvidenceEnd != nil)` is GONE (one predicate, spelled once; the check walks all 32 input combinations against a transcription of the old filter); `extension Shift { deliveryRow(sessionWorkerId:) }`; DeliveryAttempt.stamp() in pushOpen (after BOTH local guards, before ShiftFlowAPI.open) and pushClose (after the skip-another-account guard, before ShiftFlowAPI.close), nowhere else in the engine.
- DeliveryStatusViews.swift (new, SwiftUI, no surface of its own, red only for the blocked row): DeliveryStatusRows(rows:signedOut:) draws NOTHING when empty, else a blocked row then a waiting row (.bordered, roundedRectangle border shape, controlSize large, minHeight 44, glyph + count + chevron), both opening one DeliveryDetailsSheet (.medium/.large, scrolls, the Close button sits OUTSIDE the scroll view so it is always on screen). Last attempt arrives through @AppStorage.
- ContentView.swift: SignInView gets `@Query allShifts` + DeliveryStatusRows(signedOut: true) between the brand block and the code form; LogView gets phoneRows (the one deviceWide() read), deliveryRows (= settled(phoneRows)), a deliveryTick @State and ONE display-only `.task(id: deliverySettleAt)`; the idle list shows DeliveryStatusRows right after the unresolved banner (NOT wrapped in a Section); the proof-close in the shift-evidence sheet stamps the attempt (one line, before its request); ShiftScreen call gets `deliveryRows:` between onScan and syncError.
- ShiftScreen.swift: `let deliveryRows: [PendingRow]` and ONE unconditional DeliveryStatusRows after the resolver card (the stack still has exactly its four conditionals).
- WorkerScope.swift: `deviceWide()` - the named unscoped read.
- Localizable.xcstrings: 9 keys (Delivery, the blocked detail, the two waiting sentences, 'Earliest shift start: %@', 'Last attempt: %@', 'No delivery attempt yet.', two plurals). The compiler's own .stringsdata for DeliveryStatusViews.swift lists exactly 12 keys (those 9 occurrences + 'Close') and all are in the catalogue.
- checks: pending-work-check.swift (new, wired into run.sh), worker-scope-check.swift and localisation-check.swift extended.

DECISIONS TAKEN WHERE THE TASK LEFT A QUESTION
1. "never says 'automatically'" (criterion #9) vs "German verbatim from Android": they collide on ONE string. Android's blocked detail says "will not retry automatically" / "nicht automatisch erneut gesendet". On iOS nothing retries automatically, so the sentence is reworded to "are not sent again" / "nicht erneut gesendet" (adverb dropped, nothing else changed) and the check asserts the pair to the character. Every other German string is Android's verbatim (read out of strings.xml by script; the check re-reads it). The one place the adjective survives is "Automatic delivery is not currently active" / "Die automatische Übertragung ist derzeit nicht aktiv" - the sentence the task mandates; the check allows "automatic" only next to "not currently active" / "nicht aktiv".
2. The waiting sentence has a third arm Android does not: when EVERY waiting row belongs to another account than the signed-in one, the sheet says the sign-in sentence, not "open the app" (opening the app as B cannot send A's close; P3's pushClose skip keeps such rows waiting, not blocked). In a mix, the signed-in worker's own rows win. This needed `queuedByAnotherAccount` on the row and `waitingForOthers` in the summary. No new string.
3. The finish held for proof / the 422 proof_required reopen (merged shift-evidence): a reopened row is open again with its open acknowledged -> NOT pending; a finish owed with a proof (pendingEvidenceEnd != nil, row still open locally) IS waiting, because syncPending pushes it. Both pinned.
4. IN-FLIGHT GRACE (not in the task text): iOS writes the row before the POST, so every online clock-in AND clock-out is "not delivered" for one request; without a grace the idle list would pop "1 shift still on this phone" in and out after every normal tap. A WAITING row whose last local write (finish, else start) is younger than PendingNotice.grace (2 s) is held back (blocked rows never, an old row never, a negative age - a skewed clock - never). The wake-up is one display-only task in LogView (a failed push changes no row after the first ~50 ms, nothing else would redraw). The views stay pure of the clock. Pinned: the grace equals PendingNotice.grace by text.
5. Last attempt is ONE global UserDefaults date (the task's design), shown only when it is not earlier than the earliest unsent start. The proof-close in ContentView stamps too (one line) so a failed photo-close does not read "No delivery attempt yet."; resolveShift does not (it is not an outbox row).
6. Sections: the rows are NOT wrapped in a Section on the idle list and in the sign-in Form (an empty Section still draws a gap). Verified with a throwaway harness: with nothing pending the VStack spacing of the running screen is unchanged (one 24 pt gap, not two).
7. Border shape: .roundedRectangle, not the iOS 26 capsule - at AX text sizes a wrapped count turned a capsule into an ellipse around the text (seen in the harness, fixed, pinned). "Bordered" per the task = .buttonStyle(.bordered) (the house corrective style); the Blue Hour reskin restyles the container.
8. 'Earliest shift start' is the earliest of waiting AND blocked (Android, and the task's check list). In a mix where a WAITING row is older than the BLOCKED one, the time under the blocked detail is not the blocked row's; inherited from Android, not changed.
9. Glyphs: xmark.octagon.fill for blocked (the glyph ShiftRow and PendingNoticeView already use for a refused row), clock for waiting - iOS-consistent rather than Android's drawn circle-with-bang.
10. Android's `armed` input, delivery_automatic and pending_force_stop_note are NOT ported (decision-82 section 4).

VERIFIED
- NFCTimeSheets/checks/run.sh: every check green, incl. "pending-work-check: OK", "worker-scope-check: OK", "schedule-check: OK", "pending-notice-check: OK", "shift-signal-check: OK" (P3/P4/P5 text pins untouched and holding: deliveryRows was inserted between onScan and syncError so the call-site argument-order pins hold; the running stack keeps its four conditionals), "localisation-check: OK (328 keys, all German)" (319 + 9), "checks: OK".
- node ops/check-branding.mjs: 14 lines, all "ok", "check-branding: OK"; no TODO line and no non-ok line on this branch.
- Debug and Release builds (generic/platform=iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED both; zero warnings in the files this package touched (the only warnings are the pre-existing MaterialStore.swift:54 and WriteGuard.swift:122). No edit to project.pbxproj or NFCTimeSheets.entitlements.
- RED CASES reproduced against a scratch copy of the real files (scratchpad mut-p6.py; the worktree's sha256s were identical before and after, the copy byte-identical after every restore): 52 mutations, every one RED in its target check with the expected assertion text, 3 controls (a comment, a harmless statement, a harmless line in the sync pass) stayed GREEN. Groups: count (isFullySynced forgets "still open"; a proof-owed finish not waiting; blocked folded into waiting; oldest skipping blocked / picking the newest; a stale attempt shown; signed-out saying "open the app"; a sentence under a count not on screen; the stamp writing nothing; a blocked foreign row counted as waiting-for-others; all-foreign keeping "open the app"), engine (syncPending back to an inline filter; stamp before the guards; pushClose never stamping; record() stamping; the mapping forgetting the owed proof; the proof-close not stamping), views (a hard-coded background; rows not vanishing when empty; waiting before blocked; .disabled; an @Query; a drifted sentence; a second sheet control; a row under 44 pt; a capsule; Close inside the scroll view), strings (German 'automatisch'; the blocked detail back to Android's; the English plural lost; a drifted German; 'Gebäude'), placement (rows below Recent; wrapped in a Section; above the clock; a fifth conditional; the sign-in wording on the wrong screen; a tap / refresh / the signals reading the summary), device-wide (a tap toggling deviceWide(); History listing it; LogView's rows narrowed to the worker; deviceWide() dropping legacy rows; an unscoped query under another name), grace (a blocked row held back; a skewed clock hiding a row; the grace drifting from PendingNotice's; LogView not settling; the wake-up task pushing; a finish judged by the shift's start; held rows never woken). First FAIL lines, e.g. "FAIL: an open shift whose OPEN landed is NOT pending: the server has it and it waits for a tap that has not happened yet", "FAIL: syncPending iterates exactly the rows PendingWork calls WAITING - one predicate, spelled once", "FAIL: no delivery string may promise automatic delivery or mention force-stopping (iOS has neither): ...", "FAIL: deviceWide() appears in ContentView.swift only as the delivery summary's two inputs ...".
- THROWAWAY VISUAL HARNESS (scratchpad p6h, NOT committed, NOT a driven walk of the app): the REAL PendingWork.swift + DeliveryStatusViews.swift + the compiled REAL catalogue in a tiny SwiftUI app on an iPhone 17 (iOS 26.5) simulator, drawn inside the three containers they live in (a List with Sections, the running screen's ScrollView/VStack, the sign-in Form). Seen: rows render, blocked first and red, tapping a row opens the sheet; the empty case adds no gap and no extra VStack spacing; German and English; plural 1/3; the sign-in sentence; "Zuletzt versucht" / "No delivery attempt yet."; at accessibility-large (200%) the German rows wrap to three lines and stay far above 44 pt; Close stays on screen in a .medium sheet at 200%.

NOT VERIFIED (criteria #2-#11 stay open)
- Every row of the matrix as a walk of the real app (a worker session, a stopped server, a real 422 unknown_location / zone_unverified, a sign-out with unsent rows, two accounts on one phone). That a tap in the real idle List / sign-in Form opens the sheet (seen only in the harness, same containers); that VoiceOver reads a row as "N shifts ..., button"; the sheet's presentation over the real NavigationStack; that the 2 s wake-up re-renders the real LogView at the right moment (unit-proven rule + text-pinned wiring, not seen); that the grace keeps an online tap from flashing a row (same).
- The Android check (android/checks/run.sh) was not run: no Android file was touched.

RESKIN COLLISIONS (B1-B5 must touch these): (1) DeliveryStatusRows / DeliveryDetailsSheet are bare: system .bordered buttons (roundedRectangle), the red of a blocked row, system fonts; B1's tokens decide colours and B3's on-blue ink for the running screen (there is no `ink` parameter yet). (2) pending-work-check pins the CURRENT structure as text: the rows between the resolver card and notifications-off, after BOTH controls; the idle rows right after the unresolved banner and NOT in a Section; the sign-in rows between the brand block and the code form; the ShiftScreen call-site order (deliveryRows before syncError); no surface in the views; a reskin that moves things updates those assertions in the same commit. (3) The running screen's stack order pins from P5 and P4 are untouched.

PINS CHANGED: worker-scope-check.swift (b) "every use of allShifts goes through the helper" gained ONE allowed prefix, `.deviceWide()`, and was TIGHTENED in the same commit: deviceWide() may appear in ContentView.swift only as the exact two delivery-row lines, never in MaterialsView, History, handleTap, the tab lock, currentRunning or startManual. localisation-check.swift's plural guard gained the two new keys plus an assertion that their English plural exists (the key is the 'other' form: without it a count of 1 reads "1 shifts"). No pin was deleted or loosened; schedule-check, pending-notice-check and shift-signal-check are byte-identical.
<!-- SECTION:NOTES:END -->
