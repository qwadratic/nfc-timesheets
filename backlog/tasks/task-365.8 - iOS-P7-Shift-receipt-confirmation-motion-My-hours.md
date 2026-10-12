---
id: TASK-365.8
title: 'iOS P7: Shift receipt, confirmation motion, My hours'
status: In Progress
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-12 11:50'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.7
parent_task_id: TASK-365
priority: medium
ordinal: 292000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After a finish the idle list shows a 'Shift finished' receipt until Continue; the ring-then-check plays once only after a clean server acknowledgement; Settings gains a read-only 'My hours' list of the last 60 days from the server.
## Decision to record FIRST (decision-80)
Record decision-80: iOS gets 'My hours', the read-only server list of the worker's last 60 days (TASK-189 parity)?
Context: Android has had More > 'Meine Stunden' since 2026-08-24: GET /shifts/mine?since=now-60d on every entry, never cached, rows with building, state word, date, start, end, duration in Europe/Vienna, no totals or rates, no writes. iOS History shows only local rows, so an admin correction or a shift from another device is invisible. ShiftAPI.mine(since:) already exists. It is a pre-range gap and not named in the owner's D wording (confirmation state, ack animation, receipt, delivery status), so scope needs a yes.
Recommendation (planned as accepted): Include: low risk, one Settings row, and it is what a customer sees when asking 'what did the office record'. Planned as accepted; it is detachable.

## Items (Android evidence at 60f6886)
### clock-out-receipt - After a finish the idle screen shows a 'Schicht beendet' receipt until the worker presses Weiter  [PORT, size M, in_range]
- Android at 60f6886: If the newest closed local shift ended 0-120 s ago when the idle screen composes (state keyed on clientUuid+endTime, rememberSaveable), the start card is replaced by CompletedShiftReceipt: 'Schicht beendet', building, 'HH:mm – HH:mm', duration, 'Korrigiert' if corrected, 'Automatisch beendet' (error colour) if it needs resolution, and one delivery line (sync error / 'Gesendet' / 'Auf diesem Telefon gespeichert · noch nicht bestätigt'). Full-width 'Weiter' dismisses; no timeout; inline (not a dialog) so taps and tabs work; that row is hidden from Recent meanwhile.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:970-975,1011-1019,1032-1034,1572-1604; android/app/src/main/res/values/strings.xml:659,668,673; docs/ANDROID-WORKER-DESIGN.md:38-40
- iOS gap: After a clock-out iOS drops straight to the idle list; the finished shift is just the first Recent row. (ContentView's existing receipt state belongs to the unrelated MigrationReceiptSheet.)
- Port notes: LogView.idleList: receipt Section in place of the start block when recent.first ended within 120 s and a dismissed key (clientUuid+endTime) does not match; hold the eligibility in @State so it does not vanish while read; filter the row out of Recent. Reuse ShiftRow sync logic, pills incl. the iOS 'Manual' pill, fmtDur (do not change fmtDur itself). New de+en keys 'Shift finished'/'Schicht beendet', 'Continue'/'Weiter', '%@ – %@', saved-locally sentence. Inline, never a sheet/alert. Simulator: ShiftMockFlow manualStart then manualStop.

### ack-confirmation-animation - One-shot 900 ms ring-then-check plays only after the server acknowledged a clock-in or clock-out  [PORT, size M, in_range]
- Android at 60f6886: confirmationProgress(identity, confirmed, eventTime, kind): plays once when confirmed (clock-in: open acked, no sync error, not overdue; clock-out receipt: fully synced, no error, not needing resolution), event at most 45 s old, identity ('locationId:startTime' / 'clientUuid:endTime') not yet consumed. Identity is written to SharedPreferences 'worker-motion' (keys clock-in/clock-out) BEFORE animating. Stages: ring 0-430 ms (88dp, 2.8dp stroke, scale .92->1), check 390-570, fade up 600-720, time/receipt fades in 720-900. Never for pending/failed; animator scale 0 = instant; nothing waits on it.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/ShiftTimeDisplay.kt:35-73,111-138; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1188,1215-1221,1576-1598; docs/ANDROID-WORKER-DESIGN.md:46-63
- iOS gap: iOS has no acknowledgement moment; the clock card looks the same before and after the server accepts.
- Port notes: Needs the pending flag and (for clock-out) the receipt. Foundation-only gate (shouldPlay(identity, confirmed, eventTime, now, lastConsumed); stage maths) with checks/worker-motion-check.swift in run.sh; SwiftUI trim-animated Circle + check Path; consumed identity in UserDefaults before starting; skip under accessibilityReduceMotion. Trigger on the confirmed flip, not first appearance. Ink colour, never green (decision-60). No strings. Ship last.

### my-hours-screen - 'Meine Stunden': read-only server list of the worker's last 60 days  [PORT, size M, pre_existing]
- Android at 60f6886: More > 'Meine Stunden': GET /shifts/mine?since=now-60d on every entry, never cached; spinner; offline/error sentence + Aktualisieren; empty text; rows: building, state word (Läuft / Automatisch beendet / Korrigiert / Abgeschlossen), Datum, Beginn, Ende or 'Noch kein Ende', Dauer, in Europe/Vienna. No totals, rates or writes. Since dd3f244 (2026-08-24); the range only moved its entry row.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2150-2154,2185,2245-2363; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:1004-1015; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/net/Api.kt:476-481
- iOS gap: No such screen; ShiftAPI.mine(since:) exists but is only used by the migration. History shows local rows only, so an admin correction or another device's shift is invisible.
- Port notes: New MyHoursView pushed from SettingsView: .task calls ShiftAPI.mine(since: now-60d); loading/failed(offline)/loaded; rows from WireShift (locationName ?? 'Unknown location', needsResolution, correctedAt, endTime), Vienna formatting, show the 'Manual' pill. de+en keys from myhours_* and status_closed. Needs a DEBUG canned list or loopback server on the Simulator. Confirm with the owner it belongs in this port (pre-range gap).

## Files
Modify: NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/ShiftScreen.swift, NFCTimeSheets/NFCTimeSheets/Localizable.xcstrings, NFCTimeSheets/checks/run.sh
Create: NFCTimeSheets/NFCTimeSheets/ShiftReceipt.swift, NFCTimeSheets/NFCTimeSheets/ShiftReceiptView.swift, NFCTimeSheets/NFCTimeSheets/ConfirmationMotion.swift, NFCTimeSheets/NFCTimeSheets/ConfirmationMark.swift, NFCTimeSheets/NFCTimeSheets/MyHours.swift, NFCTimeSheets/NFCTimeSheets/MyHoursView.swift, NFCTimeSheets/checks/shift-receipt-check.swift, NFCTimeSheets/checks/worker-motion-check.swift, NFCTimeSheets/checks/my-hours-check.swift
## Server contract
GET /shifts/mine?since=<iso8601> (ShiftAPI.mine, API.swift:568) -> {shifts:[WireShift]} for the session worker, newest first; location_name is the BUILDING (shift insert stores place.location_id, server/routes/app.js:212).

## Strings
English keys: 'Shift finished' (worker_receipt_title), 'Continue' (worker_receipt_done), 'My hours' (myhours_open/title), 'Your shifts from the last 60 days, as stored on the server.', 'No shifts in this period.', 'No connection. Your hours can't be loaded right now.', 'Your hours could not be loaded.', 'Closed' (status_closed), 'Date: %@', 'Start: %@', 'End: %@', 'No end yet', 'Duration: %@'; reuse existing 'In progress', 'Auto-closed', 'Corrected', 'Manual', 'Refresh' (P5). German from Android values/strings.xml.

## Checks
- NEW shift-receipt-check.swift (cat ShiftReceipt): eligible only when the newest closed row ended 0-120 s ago; key = clientUuid+endTime; stays offered once captured (even after 120 s) until dismissed; dismissed key never re-offers; a different row re-offers
- NEW worker-motion-check.swift (cat ConfirmationMotion): shouldPlay(identity, confirmed, eventTime, now, lastConsumed) true only when confirmed, age 0...45 s and identity not consumed; identity consumed BEFORE animating and also under Reduce Motion; clock-in and clock-out keys independent; pending/blocked never plays; stage maths ported from ShiftTimeDisplay.kt:111-138: ring=clamp(p/0.48), check=clamp((p-0.43)/0.2), exit=clamp((p-0.67)/0.13), content alpha clamp((p-0.8)/0.2), 900 ms
- NEW my-hours-check.swift (cat Branding, TagLink, API, MyHours, ViennaTime, LoadGuard): status order endTime nil -> running, needsResolution -> auto-closed, correctedAt -> corrected, else closed (TimeSheetApp.kt myHoursStatusRes); duration omitted for the open row; Vienna formatting
- wire all three into run.sh; localisation-check.swift green

## Design rules from the plan
- OD4 (decision-80 proposal): My hours is a pre-range gap (TASK-189); planned as accepted. It is isolated (two files + one Settings row) and can be dropped without touching the rest of the package.
- Receipt: a Section at the TOP of the idle List when eligible (Android replaces the start card; on iOS the scan/manual Sections sit below Recent, ContentView.swift:362-399, so putting it in their place would hide it under up to five rows). While shown, the scan/manual start Sections are hidden and that row is filtered out of Recent. Eligibility captured once into @State (survives the 120 s window) and dismissed key kept in @State; inline, never a sheet/alert, so taps, tabs, the resolver banner and the resolver sheet keep working. Content: 'Shift finished', building, time range, duration via fmtDur (do not change fmtDur), 'Manual'/'Corrected'/'Auto-closed' pills reusing ShiftRow, delivery line (error / 'Sent' / 'Saved on this phone · not yet confirmed'), full-width 'Continue'. iOS closes locally before the server answers, so queued and blocked states must render here. Name the new type ShiftReceipt* - FinishCard.swift is an unrelated operator file.
- Ack motion: ConfirmationMark(ink:) draws Circle().trim + check Path over 900 ms, ink supplied by the caller (never green, decision-60); caller positions it; accessibilityHidden. Trigger .onChange(of: confirmed, initial: true) on the clock card (identity 'locationId:startTime', eventTime = startTime) and on the receipt (identity 'clientUuid:endTime') - equivalent to Android's LaunchedEffect(identity, confirmed); a restored/adopted old shift is excluded by the 45 s window, a queued one by confirmed==false. Consume the identity in UserDefaults keys for clock-in and clock-out BEFORE animating; skip the animation under accessibilityReduceMotion. Nothing waits on it; it never writes a shift or delays handleTap/arm/sync. confirmed comes from P5.
- My hours: MyHoursView pushed from SettingsView (new row 'My hours' + window sentence); .task calls ShiftAPI.mine(since: now-60d) with the LoadGuard token; Loading / Failed(offline = status 0) with 'Refresh' / Loaded; rows: building (locationName ?? 'Unknown location'), status word, 'Manual' pill, Date, Start, End or 'No end yet', Duration - Vienna time via P4's ViennaTime, never a rate or total, never cached.
- RISK: SwiftUI republishes @Query late - the confirmed flip must be read from the Shift row, not a copy. ShiftScreen content sits in a minute TimelineView: keep animation state in the child ConfirmationMark.

## Verification matrix (drive it; do not assert from source)
Receipt (+) | online tap-in then tap-out | idle shows 'Shift finished': building, range, duration, delivery 'Sent'; scan/manual Sections hidden; Recent excludes it; Continue returns the start Sections | server closed row
Receipt persists (+) | wait >120 s with it open | still shown until Continue; relaunch after 120 s shows none
Receipt offline (-) | Stop with server down | delivery line 'Saved on this phone · not yet confirmed' then 'Sent' after refresh
Receipt manual stop (+) | Finish without a tag | 'Manual' + 'Corrected' | manual_close, corrected_at set
Receipt auto-switch (-) | tap other building while open | previous row 'Auto-closed' (red) and the resolver banner is NOT hidden
Tap while receipt (+) | tap a card with receipt up | new shift starts, receipt gone
Ack in (+) | online tap-in | ring then check once (~900 ms) after the server answer; second launch, tab return, resume do not replay
Ack (-) | offline tap-in; late ack >45 s; blocked row | never animates
Ack out (+) | online tap-out | plays once on the receipt
Reduce Motion | enable, tap-in | no animation, identity consumed
My hours (+) | Settings > My hours | rows with building name (not 'Unknown location'), status, Vienna date/start/end/duration; open row 'No end yet', no duration | GET /shifts/mine 200
My hours (-) | empty / server down / 401 | empty sentence / offline sentence + Refresh / signed out
My hours (+) | admin-corrected shift | shows 'Corrected' | server corrected_at
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 decision-80 recorded (backlog decision create) BEFORE the code, and listed in the epic
- [ ] #2 Driven: Receipt (+) | online tap-in then tap-out | idle shows 'Shift finished': building, range, duration, delivery 'Sent'; scan/manual Sections hidden; Recent excludes it; Continue returns the start Sections | server closed row
- [ ] #3 Driven: Receipt persists (+) | wait >120 s with it open | still shown until Continue; relaunch after 120 s shows none
- [ ] #4 Driven: Receipt offline (-) | Stop with server down | delivery line 'Saved on this phone · not yet confirmed' then 'Sent' after refresh
- [ ] #5 Driven: Receipt manual stop (+) | Finish without a tag | 'Manual' + 'Corrected' | manual_close, corrected_at set
- [ ] #6 Driven: Receipt auto-switch (-) | tap other building while open | previous row 'Auto-closed' (red) and the resolver banner is NOT hidden
- [ ] #7 Driven: Tap while receipt (+) | tap a card with receipt up | new shift starts, receipt gone
- [ ] #8 Driven: Ack in (+) | online tap-in | ring then check once (~900 ms) after the server answer; second launch, tab return, resume do not replay
- [ ] #9 Driven: Ack (-) | offline tap-in; late ack >45 s; blocked row | never animates
- [ ] #10 Driven: Ack out (+) | online tap-out | plays once on the receipt
- [ ] #11 Driven: Reduce Motion | enable, tap-in | no animation, identity consumed
- [ ] #12 Driven: My hours (+) | Settings > My hours | rows with building name (not 'Unknown location'), status, Vienna date/start/end/duration; open row 'No end yet', no duration | GET /shifts/mine 200
- [ ] #13 Driven: My hours (-) | empty / server down / 401 | empty sentence / offline sentence + Refresh / signed out
- [ ] #14 Driven: My hours (+) | admin-corrected shift | shows 'Corrected' | server corrected_at
- [x] #15 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #16 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [x] #17 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [x] #18 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision number: the plan called this decision-78/79/80, but 77 and 78 are taken by branch admin-declutter and 79 is manual start. Record it with backlog decision create (next free number) BEFORE the code.

2026-10-12 iOS P7 implementation complete on branch ios-worker-parity (decision commit f4dea60, code commit 7e9bb4e, "ios: finished-shift receipt, ring-then-check only after a clean ACK, read-only My hours (P7, decision-83)"). Status stays In Progress: criteria #2-#14 are DRIVEN walks that need a signed-in WORKER session against a server, and no rig provides one (decision-50 retired the Apple-token path; TASK-365.22 is that rig, not yet built). Nothing in the matrix was driven against the app and nothing is claimed as driven. Criteria #1, #15, #16, #17, #18 are met and ticked.

DECISION: recorded as decision-83 BEFORE any code (backlog decision create, status accepted; this task's text calls it decision-80 / OD4 - 80 is the schedule, 81 manual start, 82 delivery status). AGENTS.md checklist has the pointer line; the epic's notes list it.

WHAT CHANGED
- ConfirmationMotion.swift (new, Foundation-only): the gate `decide` / `shouldPlay(identity, confirmed, eventTime, now, lastConsumed)` (confirmed AND whole seconds since the event, FLOORED like Java's Duration.seconds, in 0...45 AND identity not consumed; Decision = nothing | consume | play); `claim(_:identity:confirmed:eventTime:now:in:)` writes the identity into UserDefaults (keys worker-motion.clock-in / worker-motion.clock-out) BEFORE it returns a verdict, for every confirmed unconsumed identity (the late one included); `animates(_:reduceMotion:)`; identities 'locationId:startMillis' / 'clientUuid:endMillis'; `stage(progress:)` = Android's arithmetic to the constant (ring p/0.48, check (p-0.43)/0.2, exit (p-0.67)/0.13, content (p-0.80)/0.20, mark scale .92+.08*min(p/.48,1)-exit*.15, lift -exit*20 / (1-content)*12, arc -90+25*ring sweeping 335*ring) on a linear 0.9 s clock.
- ConfirmationMark.swift (new, SwiftUI): ConfirmationMark (Circle().trim + a check Shape, 88 pt, 2.8 pt, accessibilityHidden, no colour of its own) and the `.confirmationMotion(kind:identity:confirmed:eventTime:ink:)` host modifier: a PAUSED TimelineView when settled, @State startedAt in the modifier (a child, so ShiftScreen's minute tick cannot restart it), `.onChange(of: Trigger(identity, confirmed), initial: true)` -> begin(): reset, bail unless confirmed, CLAIM, bail unless animates(decision, reduceMotion:), only then startedAt = .now. `@Environment(\.accessibilityReduceMotion)`.
- ShiftReceipt.swift (new, Foundation-only): isRecent (0...120 whole seconds), Identity (client_uuid + finish time, 1 s tolerance), Memory {captured, dismissed} with offer(for:now:) / observe / dismiss, delivery(row:syncError:now:) = problem | sent | sending | savedLocally from PendingWork's ONE predicate, isConfirmed (the clock-out gate), badges.
- ShiftReceiptView.swift (new, SwiftUI, no surface of its own): heading, building, 'a - b', fmtDur UNCHANGED, shared pills (Manual / Corrected / Auto-closed), ONE delivery line, full-width explicit-style Continue; the motion wraps the text block, not Continue. Reads the Shift row itself in body.
- MyHours.swift (new): MyHours.status(of:) (no end first, needs-resolution, corrected, else closed), Row, windowDays 60, MyHoursState (loading / loaded / failed(offline:)) with after(failure:) (status 0 = offline, 401 = nothing, else generic), MyHoursStore (injectable fetch + clock, LoadGuard, unstructured Task, cancel()).
- MyHoursView.swift (new, SwiftUI, no surface of its own): window sentence, loading / failed + Refresh (announced) / empty / rows (building verbatim else 'Unknown location', Manual pill, status pill, Date / Start / End or 'No end yet' / Duration only when finished, ViennaTime).
- ContentView.swift: LogView gets `receiptMemory` (@State), `receiptShift`, `recentRows`; the idle list gets the receipt Section after the unresolved banner and before the delivery rows, Recent over `recentRows` (header hidden when the receipt shows the only row), the scan block and 'Start without a tag' inside `if receiptShift == nil`, and `.onChange(of: recent.first?.receiptIdentity, initial: true)` on the List; Settings gets `NavigationLink("My hours") { MyHoursView(worker: worker) }` in the identity section; `pill` is no longer private (the receipt and My hours draw the same pills). handleTap, finishManualStop, prepareCompletion, refresh(), the sync pass and the signals are untouched.
- ShiftScreen.swift: ONE `.confirmationMotion(...)` call inside clock(), before .frame - identity locationId:startTime, confirmed = ShiftSignal.isConfirmed(running, now: now, hasSyncError: ...), eventTime = the start, ink .primary. The card is still one accessibility element; the stack's four conditionals are unchanged.
- Localizable.xcstrings: 14 keys (Shift finished, Continue, '%@ – %@', My hours, the window sentence, the empty / offline / error sentences, Date / Start / End / No end yet / Duration, Closed). German verbatim from Android 60f6886 values/strings.xml (the offline English key is ASCII-apostrophe house style). Reused: In progress, Auto-closed, Corrected, Manual, Refresh, Unknown location, Sent, Sending…, Saved on this phone · not yet confirmed.
- checks: shift-receipt-check.swift, worker-motion-check.swift, my-hours-check.swift (new, wired into run.sh). No existing check was edited.

DECISIONS TAKEN WHERE THE TASK LEFT A QUESTION (decision-83 carries 1-4)
1. THE DELIVERY LINE is Android's rule (a recorded sentence first) plus two deliberate differences: an in-flight 'Sending…' for a request inside the 2 s grace (iOS writes before it posts; without it every normal online stop flashes 'not confirmed'), and a DELIVERED row that still needs resolution says 'Sent' beside the red Auto-closed pill (Android prints 'saved on this phone' there only because it reuses the motion's flag). The matrix row 'Receipt offline | delivery line Saved on this phone · not yet confirmed' therefore reads, for a stop with the server unreachable, the row's OWN sentence 'No connection - will send when you're back online.' (Android's rule and the same sentence P5's notice shows); 'Saved on this phone · not yet confirmed' appears when no error is recorded and the grace is over (e.g. the app was killed before the push finished). Owner call if the generic line should win.
2. IDENTITY with a 1 s tolerance, not an exact key: apply() overwrites endTime with the server's millisecond echo, so an exact key would change when the ACK lands and a dismissed receipt would come back. Pinned both ways (a ms echo is the same finish; a second apart is a new one).
3. THE TRIGGER: the task text says both 'on the flip, not first appearance' and `.onChange(of: confirmed, initial: true)` equivalent to Android's LaunchedEffect(identity, confirmed). Implemented the latter (Android fires on first composition too): an adopted / restored old shift is excluded by the 45 s window, a queued one by confirmed == false, a second sight by the consumed identity.
4. 45 s is Android's whole-second FLOOR (0...45), so an event 45.9 s old still plays and 46.0 does not; a finish in the future never plays and is consumed.
5. Placement: after the unresolved banner (Android's order: banner, receipt, delivery, plan, recent), not above it. The banner stays on screen.
6. @State, not @SceneStorage (as the task says): a system-killed-and-restored process re-offers the receipt only while its finish is under two minutes old; Android's rememberSaveable survives that. Documented in decision-83.
7. My hours: the window sentence is on the screen (Android), not duplicated under the Settings row; no pull-to-refresh (Android has Refresh in the failure state only); a pushed screen cancels its request on disappear; strict decode like the migration's.
8. 'Auto-closed' German stays the existing abbreviated "Autom. beendet" (a pill is narrow; Android's full "Automatisch beendet" is the word in its own receipt). Reused key, not retranslated.
9. Hiding the in-app Scan and 'Start without a tag' while the receipt is up is what the plan asked (Android replaces its start card); a background tag tap is unaffected and Continue is one tap away. Flagged because invariant (a) says the receipt never gates a tap: the in-app scan button is the one control it hides.

VERIFIED
- NFCTimeSheets/checks/run.sh: every check green, incl. "shift-receipt-check: OK", "worker-motion-check: OK", "my-hours-check: OK", "localisation-check: OK (342 keys, all German)" (328 + 14), "checks: OK". The P3-P6 text pins (worker-scope, schedule, pending-notice, pending-work, shift-signal) all held WITHOUT edits: the receipt sits between the banner and the delivery rows, the running stack keeps its four conditionals, clock() keeps its single else and its accessibility element, none of the new ContentView.swift lines contains the word schedule (the eight expected mentions are the only ones), and the foreground scenePhase handler is still the last one in the file.
- node ops/check-branding.mjs: 14 lines, all "ok", "check-branding: OK"; no TODO line and no non-ok line.
- Debug and Release builds (generic/platform=iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED both; no warning in the files this package touched (only the pre-existing MaterialStore.swift:54 and WriteGuard.swift:122). No edit to project.pbxproj or NFCTimeSheets.entitlements. The builds left Localizable.xcstrings and the sources byte-identical.
- RED CASES reproduced against a scratch copy of the real files (scratchpad p7/mut-p7.py; worktree sha256s identical before and after): 69 mutations, every one RED in its target check with the expected assertion text, and 5 stay-GREEN controls (a comment in each of the three pure files, a comment in Sync.swift, and the equivalent reorder of needs-resolution / corrected). Examples: window 46 s -> "FAIL: a LATE ACK (the event is 46.0 s old) is consumed and never plays..."; a pending row plays -> "FAIL: a pending / failed / blocked row (not confirmed) NEVER plays and consumes nothing"; claim never persists -> "FAIL: the identity was written BEFORE the verdict was returned"; Reduce Motion still animates -> "FAIL: Reduce Motion: no animation"; the host starts the clock before it claims -> "FAIL: begin(): reset, bail when not confirmed, CLAIM the identity..."; green ink -> "FAIL: ConfirmationMark.swift has no green and no surface (found '.green')"; the clock card plays whenever -> "FAIL: the clock card plays for THIS start..."; handleTap starts the motion -> "FAIL: handleTap never reads the motion or the receipt"; a captured receipt vanishes -> "FAIL: a captured receipt STAYS past the 120 s window"; a dismissed one comes back -> "FAIL: a DISMISSED receipt is never re-offered"; exact identity -> "FAIL: the server's millisecond echo of the finish time is the SAME finish"; a problem hidden behind Sent -> "FAIL: a recorded problem is never hidden behind 'Sent'"; the start Sections not gated -> "FAIL: one gate, and it covers exactly the two start Sections"; a sheet receipt -> "FAIL: ShiftReceiptView.swift is inline: no .sheet("; fmtDur edited -> "FAIL: the duration is fmtDur, and fmtDur is UNCHANGED"; running shift with autoClosed -> "FAIL: no end time wins over auto-closed"; a zero duration for the running row -> "FAIL: the running row has NO duration"; window 30 days -> "FAIL: the window is 60 days"; a stale answer published -> "FAIL: a slow STALE answer never overwrites the newer one"; a 401 painted -> "FAIL: a 401 renders NOTHING"; a total added -> "FAIL: MyHoursView.swift has no total, no rate and no amount"; Vienna time reading the phone zone -> "FAIL: [America/Los_Angeles] en_GB date: winter, 08:00 CET: got '13 Jan 2026'"; the Settings row gone -> "FAIL: Settings has exactly one 'My hours' row"; refresh() asking for My hours -> "FAIL: ShiftAPI.mine(since:) is called in exactly one place".
- THROWAWAY HARNESS (scratchpad p7/harness, NOT committed, NOT a driven walk of the app): the REAL ConfirmationMotion / ConfirmationMark / ShiftReceipt / ShiftReceiptView / PendingWork / MyHours sources, the REAL Shift @Model and Shift.deliveryRow cut out of NFCTimeSheetsApp.swift / Sync.swift, and the compiled REAL catalogue in a tiny SwiftUI app on an iPhone 17 (iOS 26.5) simulator, with an in-memory SwiftData store. Flipping closeSyncedAt on the row 3 s after launch (what Sync.pushClose does) was filmed at 12 fps: the receipt text is held back, the ring draws, the check draws inside it, the pair fades up, the receipt settles with 'Sent' in about a second, and the claimed identity appears in UserDefaults. An offline row (error sentence) and an already-delivered 5-minute-old row play nothing; a delivered row that needs resolution shows 'Sent' with the red pill and plays nothing; a manual stop shows Manual + Corrected and plays; a stand-in clock card with the SAME modifier call hides the digits during the ring and fades them in. My hours rows (running / manual corrected / unknown building auto-closed / closed) drawn in Vienna time. Reduce Motion was NOT exercised on the simulator (the environment value is read-only and the gate is pinned by the check).

NOT VERIFIED (criteria #2-#14 stay open)
- Every row of the matrix as a walk of the real app (a worker session, a stopped server, a real 422, the resolver banner next to a receipt, a tag tap while the receipt is up, relaunch after 120 s, My hours against staging with a 200 / empty / down / 401). That `.onChange(initial: true)` on the real idle List fires when LogView swaps from ShiftScreen to the list; that the real LogView's 2 s wake-up moves the receipt's 'Sending…' to 'Saved on this phone'; that the minute tick of the real ShiftScreen leaves the motion alone; VoiceOver order and Reduce Motion in the real setting; Dynamic Type 200% on the receipt.
- The Android check (android/checks/run.sh) was not run: no Android file was touched.

FOUND, NOT MINE: running `xcodebuild -exportLocalizations` rewrites Localizable.xcstrings in place (marks 13 keys extractionState "stale" and adds an EMPTY entry for 'Your session ended. Sign in again.', which OperatorSession.swift:139 localises with String(localized:) and which has no catalogue entry, so it renders English on a German phone; Auth.swift:154 uses the same sentence as a plain String literal). The file was restored from git before the commit; the gap is pre-existing and outside P7. Do not run exportLocalizations in the worktree without restoring the catalogue after.

RESKIN COLLISIONS (B1-B5 must touch these): (1) ShiftReceiptView and MyHoursView are bare: system fonts and the semantic colours ShiftRow already uses (.green Sent, .orange/.red problem), the shared `pill`, a borderedProminent Continue; B1's tokens and B2's 'receipts as cards' decide the container. (2) shift-receipt-check pins the CURRENT structure as text: the receipt Section after the unresolved banner and before the delivery rows, Recent over recentRows, the start Sections inside one `if receiptShift == nil`, the `.onChange(... initial: true)` on the List, the explicit Continue style, no surface in the new views, fmtDur's spelling; my-hours-check pins the Settings row inside the 'Signed in as' Section; worker-motion-check pins the two call sites (clock() inside the card, before .frame; the receipt's text block) and begin()'s order. A reskin that moves things updates those assertions in the same commit. (3) The motion's ink is `.primary` at both call sites: B3's on-blue ink for the running screen is one argument at one call site.

PINS CHANGED: none. No existing check was edited and none was deleted or loosened; every earlier pin held on the first run.

Criterion #16 detail: every Text / Label / Button / NavigationLink / navigationTitle literal and both String(localized:) calls in ShiftReceiptView.swift and MyHoursView.swift (ConfirmationMark.swift, ConfirmationMotion.swift, ShiftReceipt.swift and MyHours.swift carry no user-visible string) was grepped and has a catalogue entry; xcodebuild -exportLocalizations extracted exactly those keys (none of the 14 new keys came back stale or missing; the only extra key it reported is the pre-existing 'Your session ended. Sign in again.' noted above).
<!-- SECTION:NOTES:END -->
