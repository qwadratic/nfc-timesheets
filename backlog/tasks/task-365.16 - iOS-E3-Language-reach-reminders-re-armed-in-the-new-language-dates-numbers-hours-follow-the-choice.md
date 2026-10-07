---
id: TASK-365.16
title: >-
  iOS E3: Language reach: reminders re-armed in the new language,
  dates/numbers/hours follow the choice
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
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
- [ ] #1 Pending reminders are re-armed in the new language on a change (iOS fixes notification text when scheduled)
- [ ] #2 Hours totals use the locale's decimal separator and a translated unit ("7,5 Std." / "7.5 h"); localisation-check gains an assertion against String(format:) with a letter unit
- [ ] #3 Dates and times use format styles, never a fixed-locale DateFormatter
- [ ] #4 The Live Activity has no extension target yet: document that its strings must come from a catalogue the resolver can reach (docs/LIVE-ACTIVITY-SETUP.md)
- [ ] #5 Driven on the simulator: switch on the signed-out screen; switch with a shift running; switch with a material draft open; relaunch; change it in iOS Settings and reopen; read a re-armed reminder
- [ ] #6 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #7 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #8 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #9 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
