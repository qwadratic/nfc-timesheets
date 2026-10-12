---
id: TASK-365.10
title: >-
  iOS B2: Reskin: idle screen (day heading, start card, action first, receipts
  as cards)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - reskin
dependencies:
  - TASK-365.9
parent_task_id: TASK-365
priority: medium
ordinal: 294000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of the Blue Hour reskin (docs/ANDROID-WORKER-DESIGN.md, TASK-363). Idle opens with today's date and "Ihr Arbeitstag", one focused glyph + one filled scan button + a quiet manual start, then pending status, upcoming work and recent shifts as cards (time range dominant). Keep manual start (decision-56) - it is a normal worker action, not a no-NFC fallback.

## Items (Android evidence at 60f6886)
### idle-day-heading - Idle Shift screen opens with today's date and the heading 'Ihr Arbeitstag'  [PORT, size S, in_range]
- Android at 60f6886: Date line 'EEEE · d MMMM' in the app locale (re-read each minute) and heading worker_day_title 'Ihr Arbeitstag' / 'Your working day'; replaces log_title.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:34-46; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:984-986; android/app/src/main/res/values/strings.xml:641
- iOS gap: Idle screen uses navigationTitle 'TimeSheet'; no date line.
- Port notes: Header row with Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)) in a TimelineView(.everyMinute) and 'Your working day' (de 'Ihr Arbeitstag') with header trait; blank/replace the idle navigationTitle; key 'TimeSheet' then unused.

### idle-start-card - Idle start block: glyph, 'Bereit für die Schicht?', hint, one filled scan button, quiet manual start  [PARTIAL, size S, in_range]
- Android at 60f6886: WorkerStartCard: 88dp entrance mark, title worker_start_title, hint log_hint_start, full-width filled 56dp 'Tag manuell scannen' (scan_open, strings.xml:434 read), text button 'Ohne Tag starten'. Replaced by the receipt while one shows.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:61-102; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1011-1019; android/app/src/main/res/values/strings.xml:434,642
- iOS gap: iOS has the hint, filled 'Scan a tag' and bordered 'Start without a tag', but no title line, as two List sections below Recent, manual start with its own footer.
- Port notes: One start block (SF Symbol in a circle, accessibilityHidden; new key 'Ready for your shift?' de 'Bereit für die Schicht?'; existing hint; .borderedProminent scan; quiet manual button). Keep the DEBUG manualMockSection reachable; keep the manual explanation in the sheet.

### idle-layout-order - Idle screen order: action first, recent shifts after  [PARTIAL, size S, in_range]
- Android at 60f6886: Order: day heading, unresolved banner, start card or receipt, delivery rows, NFC banner, planned assignment, 'Zuletzt' (5 rows or empty text), no-push note, Refresh button.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:977-1059
- iOS gap: iOS order: unresolved row, Recent, hint + Scan, Start without a tag, debug mocks, no-push note. No delivery/schedule/receipt slot.
- Port notes: Reorder idleList sections; keep pull-to-refresh instead of a Refresh button. No strings.

### shift-row-card-restyle - Shift rows become cards with the time range as the dominant line  [PARTIAL, size S, in_range]
- Android at 60f6886: ShiftRow is an 18dp WorkerCard: name + state word, date, large 'HH:mm – HH:mm', duration, delivery line.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1610-1682; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerVisuals.kt:32-40
- iOS gap: Same facts in a plain List row; range is caption-sized.
- Port notes: Purely visual, optional: restyle ShiftRow in place; keep the 'Manual' pill (decision-56 section 5). Cards in a List need clear row backgrounds for swipe-to-delete.

### shift-row-waiting-copy - Unsent rows say 'Wartet auf Verbindung' plus the last attempt time, never 'Sending…'  [PARTIAL, size S, pre_existing]
- Android at 60f6886: A row neither failed nor fully synced shows sync_waiting and 'Zuletzt versucht HH:mm' (LocalShift.lastAttemptAt) or the never-tried sentence.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1654-1679; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/data/ShiftStore.kt:195,354-355
- iOS gap: iOS shows 'Sending…' for every unacknowledged row and stores no last-attempt time.
- Port notes: Optional 'lastAttemptAt: Date?' on Shift stamped in pushOpen/pushClose; row label 'Waiting for a connection' + 'Last tried %@' / 'Not attempted yet' (take exact German from sync_waiting/sync_last_try/sync_never_tried).

## Rules
- Reskin means restyling what exists: P1-P7 will already have added their own rows/states as self-contained views; list in the final summary every collision you hit.
- Support German, English, large text (Dynamic Type), dark mode and Reduce Motion. Local glyphs hidden from accessibility.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Idle Shift screen opens with today's date and the heading 'Ihr Arbeitstag'
- [ ] #2 Idle start block: glyph, 'Bereit für die Schicht?', hint, one filled scan button, quiet manual start
- [ ] #3 Idle screen order: action first, recent shifts after
- [ ] #4 Shift rows become cards with the time range as the dominant line
- [ ] #5 Unsent rows say 'Wartet auf Verbindung' plus the last attempt time, never 'Sending…'
- [ ] #6 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [ ] #7 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #8 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #9 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #10 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
