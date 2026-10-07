---
id: TASK-365.8
title: 'iOS P7: Shift receipt, confirmation motion, My hours'
status: To Do
assignee: []
created_date: '2026-10-07 12:21'
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
- [ ] #1 decision-80 recorded (backlog decision create) BEFORE the code, and listed in the epic
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
- [ ] #15 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #16 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [ ] #17 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [ ] #18 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
