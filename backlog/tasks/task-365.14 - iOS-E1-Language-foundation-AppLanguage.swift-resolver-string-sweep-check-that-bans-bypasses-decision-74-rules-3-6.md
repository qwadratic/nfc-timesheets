---
id: TASK-365.14
title: >-
  iOS E1: Language foundation: AppLanguage.swift resolver, string sweep, check
  that bans bypasses (decision-74 rules 3, 6)
status: In Progress
assignee: []
created_date: '2026-10-07 12:22'
updated_date: '2026-10-13 01:24'
labels:
  - ios
  - parity
  - worker
  - i18n
dependencies:
  - TASK-365.13
parent_task_id: TASK-365
priority: medium
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-74 (accepted): iOS gets the same language control as Android - Deutsch / English / follow the phone, value set "" | "de" | "en", on the signed-out screen and in More; ONE value shared with the OS per-app language setting (never a second flag); applies LIVE; never in the tap path, never signs out or touches a running shift; one resolver (AppLanguage.swift, Foundation-only) through which every user-visible string resolves, enforced by a check. decision-61 rule 2 stands: German default, de+en parity. "This week" boundary stays Calendar.current (NOT language-derived).

Cost to plan for: ~164 String(localized:) call sites in 15 files plus SwiftUI views need the resolved locale in their environment, so this lands as a FOUNDATION sweep after the reskin. Reminder text is fixed when SCHEDULED on iOS (Android reads it when it fires), so reminders must be re-armed on a language change.

## Items (Android evidence at 60f6886)
### in-app-language-picker - In-app language selector (Deutsch / English / phone language), applied immediately and persisted  [BLOCKED_BY_DECISION, size M, in_range]
- Android at 60f6886: Three-segment radio group 'Sprache': 'Deutsch', 'English', 'Wie am Telefon'. AppLanguage.set accepts only '', 'de', 'en'; API 33+ writes LocaleManager.applicationLocales, below stores SharedPreferences app_language + recreate. Applies to screens, dates, operator/scan activities and notifications; survives restart; no server call; open shift and material draft survive the switch.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/LanguagePicker.kt:35-69; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/AppLanguage.kt:13-52; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:228,2192-2194
- iOS gap: iOS has no language control or override code. decision-61 (accepted, read): 'the owner ruled: use the system language on both platforms - no in-app switcher anywhere.' decision-71 (accepted, body empty, read) title: 'supersedes decision-61 for Android only at owner request'. decision-61 therefore still binds iOS.
- Port notes: Unblock only by a new decision record superseding decision-61 for iOS that names the mechanism (create via the backlog CLI). Options: (A) row showing the current language that opens UIApplication.openSettingsURLString (S, OS stays source of truth); (B) AppleLanguages + relaunch (M); (C) live switch via .environment(locale) plus explicit bundle through all String(localized:) sites and re-arming reminders (L). Strings if lifted: Language/Sprache, Deutsch, English, 'Use phone language'/'Wie am Telefon'.

### os-per-app-language-registration - App declares de and en so the OS per-app language setting lists them  [ALREADY_ON_IOS, size S, in_range]
- Android at 60f6886: android:localeConfig=@xml/locales_config lists de and en; the in-app picker writes the same OS-managed value.
- Android evidence: android/app/src/main/AndroidManifest.xml:77-78; android/app/src/main/res/xml/locales_config.xml:1-5
- iOS gap: 
- Port notes: Nothing to port: the catalogue compiles to de.lproj + en.lproj (language#4 confirmed in existing build products), which is what iOS uses for Settings > app > Language. Caveats: the row is reportedly hidden unless the phone has two or more preferred languages (UIPrefersShowingLanguageSettings is an untested community-reported key); knownRegions lacks de (cosmetic, owner's file).

### unsupported-phone-language-fallback - Fallback language for a phone the app has no translation for (German on Android, English on iOS)  [PARTIAL, size S, pre_existing]
- Android at 60f6886: 'Follow the phone' resolves against values/ (German default) and values-en/: fr-FR -> German (TASK-327). With the picker a worker can now force either.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/AppLanguage.kt:21-25; android/checks/core-check.kt:988-991
- iOS gap: iOS falls back to English (development region en) and offers no in-app way out. Predates the range.
- Port notes: Not an agent change: TASK-327 owns it (decision record + pbxproj developmentRegion/knownRegions edit by the owner).

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AppLanguage.swift is Foundation-only and maps stored value -> locale and string table; one source of truth shared with the OS per-app setting
- [x] #2 Every String(localized:) / LocalizedStringKey site resolves through it; a new check FAILS on a bypass (same spirit as localisation-check)
- [x] #3 Documented: what happens on an unsupported phone language stays with TASK-327 (owner: developmentRegion/knownRegions in pbxproj)
- [x] #4 Driven on the simulator: switch on the signed-out screen; switch with a shift running; switch with a material draft open; relaunch; change it in iOS Settings and reopen; read a re-armed reminder
- [x] #5 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #6 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #7 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #8 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 1f273a6 (branch ios-language). AppLanguage.swift (Foundation-only; cat-ed by the checks) holds the value set ("" | de | en), the selection read from the app's OWN defaults domain key AppleLanguages (the OS per-app value; "follow the phone" removes it, never a third state; a -AppleLanguages launch argument is the PHONE speaking, not a choice), the language in force (a choice, else the first phone language the app has, else Bundle.main.developmentLocalization - TASK-327's, read not hard-coded), the Locale (the phone's own when following it in its own language, else the bare language like Android's forLanguageTag) and string resolution through a LocalizedStringResource whose locale is set. Measured on the Simulator: String(localized:bundle:locale:) ignores locale for the lproj, the resource form does not - so the task's option (C) 'explicit bundle through every site' was not needed. AppLanguageModel + .appLanguage() (the LAST modifier in NFCTimeSheetsApp) put it in the root environment; nothing recreates the tree (no .id on the language: a draft, a sheet and a pushed History survive).

SWEEP: every String(localized:) is AppLanguage.string (views pass their own locale: so a switch re-evaluates them; 202 literals, all extracted by the compiler: verified against .stringsdata). Beyond the ~164 sites the task counted: a STORED sentence (a row's syncError, a refusal in @State, the location footnote, the building-switch notice) is a catalogue VALUE in whichever language was in force when it was made, so every display site of one says it again through AppLanguage.rerender (key found by exact value or by the value's pattern, ambiguous or unknown text left untouched; works on rows written by earlier builds). Two literals the sweep found shipping English: 'Your session ended. Sign in again.' (Auth.swift, a bare String) and the migration receipt's 'not finished' / 'cleared' / 'needs your admin' - now catalogue keys, de + en.

CHECKS: checks/app-language-check.swift (in run.sh) - the resolver run for real (precedence, fallback incl. development-region move, locale, persistence through an injected store, notification, throwaway de/en bundle, rerender both ways incl. the REAL catalogue), plus text pins: String(localized:) / NSLocalizedString / bundle lookup / Locale.current / the OS key outside AppLanguage.swift FAIL, root wiring, no .id on the language, every stored-sentence display site, every locale: locale has its @Environment. localisation-check gained: every AppLanguage.string literal must have a catalogue key of the same shape. Each pin reproduced RED by mutation (String(localized:) back in API.swift, rerender dropped in PendingNoticeView, .appLanguage() removed, isValid accepting anything, follow-phone stored as [""], Locale.current default on ViennaTime, .id(language) on ContentView, choice not beating the phone, a catalogue key deleted, reminders from a fixed language). AGENTS.md i18n step 3 now names AppLanguage.string.

DRIVEN (criterion #4; rig WorkerRigLanguageUITests via reskin-walk.sh, iPhone 17 Pro clone iOS 26.5, phone en AND phone de): L1 signed-out switch is live, follow-the-phone removes the choice, relaunch keeps it, signing in while chosen keeps it; L2 shift running (server: exactly one open shift after); L3 material draft open (draft still in the field, server: 0 material requests); L4 operator screens; L5 iOS Settings > Apps > NFCTimeSheets > Language shows an in-app choice with its checkmark and a Settings choice (Deutsch, or Default which removes the override) is what the app shows/selects when opened with NO launch arguments; L6 re-armed reminder - READ FROM THE PHONE'S LOG, not from a lock screen: CFBundle's debug log prints each string lookup with its localization and result (key: Still clocked in ... localizationNames: [de], result: Noch eingestempelt) and SpringBoard prints each request it receives (8x shift-reminder-Nh after the switch; title/body are <redacted> there). Not run: a DELIVERED notification on a lock screen, VoiceOver, a real NFC tap (the DEBUG tap hook starts the shift). Whole rig suite on the final build: walk.sh all 150 PASS / 0 FAIL; reskin matrix 5 combos 0 failing. Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-lang/shots (<combo>-l1..l6-*), logs/reminders-de.log, logs/reminders-en.log under the same rig home.

UNSUPPORTED PHONE LANGUAGE (criterion #3): untouched, TASK-327's. The fallback is the bundle's development language (en today, CFBundleDevelopmentRegion), READ at run time - the owner's pbxproj edit moves it with no change here; the check pins that. node ops/check-branding.mjs: 14 ok lines, no TODO line, 'check-branding: OK'. Debug and Release 'xcodebuild -scheme NFCTimeSheets -destination generic/platform=iOS Simulator CODE_SIGNING_ALLOWED=NO build' both BUILD SUCCEEDED; no edit to project.pbxproj or the entitlement (the new files are picked up by the synchronized group).
<!-- SECTION:NOTES:END -->
