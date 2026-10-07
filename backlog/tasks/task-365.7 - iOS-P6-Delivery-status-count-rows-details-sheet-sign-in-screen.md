---
id: TASK-365.7
title: 'iOS P6: Delivery status: count rows, details sheet, sign-in screen'
status: To Do
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-07 12:27'
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
- [ ] #1 decision-79 recorded (backlog decision create) BEFORE the code, and listed in the epic
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
- [ ] #12 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #13 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [ ] #14 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [ ] #15 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision number: the plan called this decision-78/79/80, but 77 and 78 are taken by branch admin-declutter and 79 is manual start. Record it with backlog decision create (next free number) BEFORE the code.
<!-- SECTION:NOTES:END -->
