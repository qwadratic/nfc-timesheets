---
id: TASK-365.16
title: >-
  iOS E3: Language reach: reminders re-armed in the new language,
  dates/numbers/hours follow the choice
status: In Progress
assignee: []
created_date: '2026-10-07 12:22'
updated_date: '2026-10-13 01:25'
labels:
  - ios
  - parity
  - worker
  - i18n
dependencies:
  - TASK-365.15
parent_task_id: TASK-365
priority: medium
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-74 (accepted): iOS gets the same language control as Android - Deutsch / English / follow the phone, value set "" | "de" | "en", on the signed-out screen and in More; ONE value shared with the OS per-app language setting (never a second flag); applies LIVE; never in the tap path, never signs out or touches a running shift; one resolver (AppLanguage.swift, Foundation-only) through which every user-visible string resolves, enforced by a check. decision-61 rule 2 stands: German default, de+en parity. "This week" boundary stays Calendar.current (NOT language-derived).

Cost to plan for: ~164 String(localized:) call sites in 15 files plus SwiftUI views need the resolved locale in their environment, so this lands as a FOUNDATION sweep after the reskin. Reminder text is fixed when SCHEDULED on iOS (Android reads it when it fires), so reminders must be re-armed on a language change.

## Items (Android evidence at 60f6886)
### notifications-follow-app-language - Notification text uses the same language as the screens  [ALREADY_ON_IOS, size S, in_range]
- Android at 60f6886: ShiftSignals.strings(context) = AppLanguage.wrap(applicationContext); reminders render when the alarm fires.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/ShiftSignals.kt:65-70,243-268,296-303
- iOS gap: 
- Port notes: Nothing to port while decision-61 stands. iOS renders text at SCHEDULE time, Android at FIRE time: after an OS language change pending rungs keep the old language until the next arm. Optional hardening: NSString.localizedUserNotificationString. New notification strings need de entries in the same commit.

### dates-times-follow-app-language - Dates and times formatted in the app language  [ALREADY_ON_IOS, size S, in_range]
- Android at 60f6886: All formatters re-localised with AppLanguage.locale(context).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/AppLanguage.kt:33-36; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2451-2493
- iOS gap: 
- Port notes: Nothing to port: Date.formatted follows the app's effective language. New ported screens must use format styles, never a fixed-locale DateFormatter.

### hours-decimal-and-unit-localised - Hours totals use the locale's decimal separator and a translated unit  [PARTIAL, size S, pre_existing]
- Android at 60f6886: History 'Diese Woche'/'Gesamt' use String.format(locale, '%.1f') in hours_format ('%1$s Std.' / '%1$s h'): '7,5 Std.' vs '7.5 h'.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2126-2135,2469-2470; android/app/src/main/res/values/strings.xml:232
- iOS gap: iOS formats with String(format: '%.1f h') and no locale: always '7.5 h', unit never through the catalogue; fmtDur ('2h 15m') is likewise literal. Predates the range.
- Port notes: ContentView.swift:842-843: String(localized:) with x.formatted(.number.precision(.fractionLength(1))) and key '%@ h' -> de '%@ Std.'. Decide separately on fmtDur (MigrationCore depends on its output). Add a localisation-check assertion against String(format: with a letter unit.

### week-start-from-app-language - 'This week' boundary derived from the app-language locale  [NOT_APPLICABLE, size S, in_range]
- Android at 60f6886: HistoryScreen uses WeekFields.of(AppLanguage.locale); choosing bare 'en' can move the week start and change the hours sum.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2102-2108
- iOS gap: iOS uses Calendar.current (region), independent of display language; porting would make a total depend on UI language.
- Port notes: Do not port; keep Calendar.current. Possible Android defect to report back.

### live-activity-language - Always-on running-shift signal wording and language (iOS Live Activity has no words yet)  [PARTIAL, size S, pre_existing]
- Android at 60f6886: Ongoing notification title/body/channel come from the app-language context and are re-posted on every foreground and after reboot.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/ShiftSignals.kt:91-127,290-306; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/Receivers.kt:57-72
- iOS gap: No widget-extension target exists, so the Live Activity renders nothing; the only always-on signal is the wordless badge. The setup doc tells the owner to hardcode a German sentence in the extension.
- Port notes: Extension target is the owner's (pbxproj). Agent-doable: amend docs/LIVE-ACTIVITY-SETUP.md step 9 so the overdue sentence is a localized key (de+en) in a catalogue with extension target membership.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pending reminders are re-armed in the new language on a change (iOS fixes notification text when scheduled)
- [x] #2 Hours totals use the locale's decimal separator and a translated unit ("7,5 Std." / "7.5 h"); localisation-check gains an assertion against String(format:) with a letter unit
- [x] #3 Dates and times use format styles, never a fixed-locale DateFormatter
- [x] #4 The Live Activity has no extension target yet: document that its strings must come from a catalogue the resolver can reach (docs/LIVE-ACTIVITY-SETUP.md)
- [x] #5 Driven on the simulator: switch on the signed-out screen; switch with a shift running; switch with a material draft open; relaunch; change it in iOS Settings and reopen; read a re-armed reminder
- [x] #6 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #7 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #8 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #9 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 1a87813 (branch ios-language). REMINDERS: LogView observes AppLanguageModel.effective and runs armIfStillCurrent() on a change - the same session-guarded, store-reading, idempotent arm the foreground return makes; ShiftSignalCenter.scheduleLadder reads AppLanguage.effective at arm time and passes it to every title and body. Not in the tap path, writes no row, pushes nothing (pinned). DATES/HOURS: AppLanguage.hours (catalogue key '%@ h' -> '%@ Std.', one decimal in the language's separator: 7,5 Std. / 7.5 h) in History's two totals instead of String(format: '%.1f h'); AppLanguage.formatted (Date.FormatStyle with the view's locale) replaces every Date.formatted(date:time:) - that call takes no locale and read the phone's. ViennaTime already took the locale (E1) and sets it on its DateFormatter; WorkerDayHeading's DateFormatter takes the environment locale. 'This week' stays Calendar.current (decision-74 rule 8; pinned: no locale or language in weekHours). fmtDur decided separately: UNCHANGED - whole numbers and h/m, and MigrationCore's classifier is defined by its output; documented at the function.

CHECKS: app-language-check section 11 runs hours (7,5 / 7.5 / 0,0 / 12.0) and formatted (24 h German vs 12 h English, dates differ) for real, pins the catalogue unit in both languages, History's week, DateFormatter locales, the LogView re-arm (and that it does nothing else) and the doc; localisation-check fails on String(format:) with a numeric conversion followed by a letter unit anywhere in the sources (reproduced RED by putting the History line back; also .formatted(date:) back in ShiftRow, the re-arm removed, the week boundary taken from the language, hours losing their decimal, the German unit drifting). LIVE ACTIVITY (#4): docs/LIVE-ACTIVITY-SETUP.md step 9 no longer says to type 'Über 8 Stunden — muss bestätigt werden' into the extension; it says AppLanguage.string("Over 8 hours") (a key that already exists in both languages) and the new step 10 names the catalogue-reachable requirement and the target membership of AppLanguage.swift + Localizable.xcstrings. No extension target exists, so nothing of this was driven; the doc says what to verify on hardware.

DRIVEN (criterion #5): L6 testL6SwitchArmsTheRemindersAgainInTheNewLanguage, phone en -> de and phone de -> en, through the driver's log-start / log-mark / log-check / log-stop: a shift is started in the phone's language, the switch is made from More, and the driver requires that AFTER it SpringBoard received the ladder again (8 shift-reminder-Nh requests) and that the ladder's words were resolved in the new language and in no other - 'key: Still clocked in ... localizationNames: [de], result: Noch eingestempelt' (7 nudge rungs + the 8 h one). HOW IT WAS READ: pending local notifications have no out-of-process reader on the Simulator (title/body are <redacted> in SpringBoard's log; the rig README says so), so what was read is CFBundle's own string-resolution debug log for the arm - the reminder's words and the language they were resolved in - not a delivered notification on a lock screen. If the owner wants that, it needs a device. Full rig suite on the final build: walk.sh all 150 PASS / 0 FAIL; reskin default matrix (5 combos x 7 steps) 0 failing; WorkerRigLanguageUITests L1-L6 x phone en/de all pass. Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-lang/shots and logs/reminders-{de,en}.log.

Gates: checks/run.sh green (31 checks, incl. the three new/extended); node ops/check-branding.mjs: 14 ok lines, no TODO/non-ok line, 'check-branding: OK' (the TASK-188 TODO line is not printed by this tree's check-branding); Debug and Release xcodebuild BUILD SUCCEEDED; no edit to project.pbxproj or NFCTimeSheets.entitlements. Known limit, said in AppLanguage.swift: text the OS draws itself from the bundle at LAUNCH (permission prompts from InfoPlist.strings, the Core NFC sheet's chrome) keeps the launch language until the next launch, from the same per-app value; nothing the app draws is in that class.
<!-- SECTION:NOTES:END -->
