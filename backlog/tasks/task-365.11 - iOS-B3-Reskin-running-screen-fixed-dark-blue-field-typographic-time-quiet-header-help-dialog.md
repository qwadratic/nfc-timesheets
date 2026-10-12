---
id: TASK-365.11
title: >-
  iOS B3: Reskin: running screen (fixed dark-blue field, typographic time, quiet
  header, help dialog)
status: In Progress
assignee: []
created_date: '2026-10-07 12:22'
updated_date: '2026-10-12 21:08'
labels:
  - ios
  - parity
  - worker
  - reskin
dependencies:
  - TASK-365.10
parent_task_id: TASK-365
priority: medium
ordinal: 295000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of the Blue Hour reskin (docs/ANDROID-WORKER-DESIGN.md, TASK-363). iOS already has a blue running screen (decision-60: never green, blue default, gradient flag-gated): this is a reskin of ShiftScreen.swift header()/clock(), not a rebuild. Drop the timer card; "SEIT BEGINN" label, large HH:MM, small seconds, tabular numerals; help behind a button. Collides with P5 (state word / pending wording) - restyle, do not rewrite.

## Items (Android evidence at 60f6886)
### running-field-fixed-dark-blue - Running screen is a solid fixed dark-blue field with light ink  [PARTIAL, size M, in_range]
- Android at 60f6886: Whole area ShiftBrand.Container #10243D (same in light/dark), ink #E6ECF5; content directly on the field; inverted filled button; light status-bar icons; overdue: error ink (flag off: errorContainer field). Notice/resolver/notification blocks stay neutral cards. No green (decision-60).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1135-1143,1175-1187; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/Theme.kt:124-138; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerVisuals.kt:99-109
- iOS gap: iOS is never-green and uses the named ShiftRunning asset, but as a 14% wash with system label colours and grey cards around clock, instruction and notices.
- Port notes: Owner design decision first. If adopted: named colour sets (not literals, decision-60 section 1), dark colorScheme for the subtree, remove card backgrounds from clock()/instruction(), light toolbar scheme; keep BlueDrift for the flag; keep red as colour AND words. Add a source-text check that ShiftScreen.swift has no '.green' or raw '.blue'.

### running-time-display - Elapsed time is typographic: 'SEIT BEGINN' label, large HH:MM, small seconds, no timer card  [PARTIAL, size M, in_range]
- Android at 60f6886: ShiftTimeDisplay: label worker_elapsed ('SEIT BEGINN' / 'TIME WORKED'), zero-padded HH:MM in tabular proportional digits fitted 32-72sp by measurement, seconds at ~32% on the same baseline; overdue shows '8:00:00+'; digits hidden from TalkBack, one merged description; state word below. White timer card removed.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/ShiftTimeDisplay.kt:59-109; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1208-1227,1333-1340; android/app/src/main/res/values/strings.xml:651
- iOS gap: iOS shows system-ticked H:MM:SS at one size (64pt bold rounded) in a grey card with 'Running'; no label, seconds not subordinate. Accessibility treatment and state word already match.
- Port notes: Minimal: drop the card, add label key 'TIME WORKED' (de 'SEIT BEGINN'), keep Text(timerInterval:). Full: a per-second TimelineView around ONLY the digits for HH:MM + small seconds, clamped at the 8h deadline. Keep the single accessibility element and 'Running' (decision-60 section 4).

### running-header-hierarchy - Running header: quiet state heading 'Schicht läuft', smaller site name, start time  [PARTIAL, size S, in_range]
- Android at 60f6886: Heading labelLarge at 80% ink: worker_active_title 'Schicht läuft' / 'Shift in progress' (replaces 'Eingestempelt'), or overdue/pending heading; building at 24sp medium; 'Begonnen um HH:mm'.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1188-1206; android/app/src/main/res/values/strings.xml:128,650
- iOS gap: Heading reads 'Clocked in' (title3, tint), building is largeTitle bold, nav bar repeats 'Shift running'.
- Port notes: Heading key with en 'Shift in progress' / de 'Schicht läuft'; building .title2 medium; decide whether the nav title moves to the same key or is removed. 'eingestempelt' stays elsewhere in the catalogue, so the house-word check holds.

### running-help-dialog - Shift help moves behind a 'Hilfe zur Schicht' button  [PORT, size S, in_range]
- Android at 60f6886: The help paragraph is no longer printed; a text button worker_help opens an AlertDialog with the unchanged shift_help text and Dismiss.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1315-1327; android/app/src/main/res/values/strings.xml:672
- iOS gap: iOS always renders the help paragraph as a card.
- Port notes: Replace helpCard with a labelled Button('Shift help', de 'Hilfe zur Schicht') presenting the existing sentence. Prefer a .sheet or inline disclosure over .alert: ShiftScreen.swift:247-250 (read) records that SwiftUI drops an alert when a sheet (the decision-10 resolver in LogView) presents at the same time.

## Rules
- Reskin means restyling what exists: P1-P7 will already have added their own rows/states as self-contained views; list in the final summary every collision you hit.
- Support German, English, large text (Dynamic Type), dark mode and Reduce Motion. Local glyphs hidden from accessibility.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Running screen is a solid fixed dark-blue field with light ink
- [x] #2 Elapsed time is typographic: 'SEIT BEGINN' label, large HH:MM, small seconds, no timer card
- [x] #3 Running header: quiet state heading 'Schicht läuft', smaller site name, start time
- [x] #4 Shift help moves behind a 'Hilfe zur Schicht' button
- [x] #5 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [x] #6 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #7 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #8 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #9 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 7f27e26 (branch ios-blue-hour-reskin). Design call (owner's proxy): inverse-filled primary button; on the field it inverts against the field (WorkerField).
Field: ShiftField #10243D / ShiftOnField #E6ECF5 (Theme.kt ShiftBrand, same in light and dark), overdue = ShiftOverdueField / ShiftOverdueInk (errorContainer / onErrorContainer) with the flag off, red ink over the blue with it on; BlueDrift kept, still behind fun_shift_screen, and holds still under Reduce Motion; no .green / raw .blue in ShiftScreen (pinned). Time: ShiftTimeDigits (own per-second TimelineView, HH:MM large + seconds at 32%, @ScaledMetric, hidden from VoiceOver; ShiftSignal.clockParts clamped to 8 h, run in shift-signal-check). Header: quiet label-weight state heading 'Schicht läuft' / 'Shift in progress', site at title2 medium; the navigation title is gone on both screens. Help: 'Shift help' DisclosureGroup (not an alert/sheet: SwiftUI drops one that presents with the decision-10 resolver sheet) - Android's AlertDialog is the only deviation.
Collisions with P1-P7: P5 (pending-notice-check re-pinned: heading word and ShiftTimeDigits instead of Text(timerInterval:); PendingNoticeView itself untouched and inherits the field ink), P7 (confirmationMotion call and its pins untouched, now over a card-less block), P4 (schedule-check helpCard -> helpButton; ScheduleSummary's title/action row now stacks at the largest text sizes - it broke 'Einsatz' one letter per line at AX5), P6 (delivery rows sit on the field with the ink as their tint ONLY, so their details sheet reads in the phone's appearance; driven).
Not proven: VoiceOver itself (the one spoken label is unchanged and pinned, the rig cannot run VoiceOver), the home-screen badge / reminders / Live Activity (unchanged, the Simulator cannot show them).
Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-reskin/shots (b3-*: running field in light-en-m, dark-en-m, light-de-m, dark-de-xxxl, light-en-xxxl; pending + delivery sheet in light-en-m and dark-de-m; overdue in light-en-m and dark-de-xxxl), driven by ops/ios-rig/reskin-walk.sh.

Commit: 25165ed (the first hash above was amended to add the rig-test fixes below). Existing rig walks re-run on the final tree, all PASS: signin, p1-same-building, p2-online-verified, p2-stop, p3-signout, p3-b-signin, p3-swipe-delete, p4-idle, p4-running, p5-online / -unreachable / -refused / -blocked / -overdue, p6-empty / -waiting / -blocked / -signin / -dynamic-type. The rig tests follow the new tab names, the idle heading and the three running state headings (runningHeading); p4-running asserts the 'Shift help' button where it asserted the printed help card.
<!-- SECTION:NOTES:END -->
