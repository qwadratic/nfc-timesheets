---
id: TASK-365.15
title: >-
  iOS E2: Language picker on the signed-out screen and in More (decision-74
  rules 1, 2, 4, 5)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - i18n
dependencies:
  - TASK-365.14
parent_task_id: TASK-365
priority: medium
ordinal: 299000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-74 (accepted): iOS gets the same language control as Android - Deutsch / English / follow the phone, value set "" | "de" | "en", on the signed-out screen and in More; ONE value shared with the OS per-app language setting (never a second flag); applies LIVE; never in the tap path, never signs out or touches a running shift; one resolver (AppLanguage.swift, Foundation-only) through which every user-visible string resolves, enforced by a check. decision-61 rule 2 stands: German default, de+en parity. "This week" boundary stays Calendar.current (NOT language-derived).

Cost to plan for: ~164 String(localized:) call sites in 15 files plus SwiftUI views need the resolved locale in their environment, so this lands as a FOUNDATION sweep after the reskin. Reminder text is fixed when SCHEDULED on iOS (Android reads it when it fires), so reminders must be re-armed on a language change.

## Items (Android evidence at 60f6886)
### language-picker-on-sign-in-screen - Language selector on the signed-out screen  [BLOCKED_BY_DECISION, size S, in_range]
- Android at 60f6886: SignInScreen renders LanguagePicker() under the brand block; the device-local choice is kept across sign-in/out.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:211-228
- iOS gap: Blocked by decision-61 ('no in-app switcher anywhere'); decision-71 is 'for Android only'.
- Port notes: Depends on in-app-language-picker being unblocked; then a Section between the brand Section and CodeSignInSection.

### language-picker-settings-card - Language selector as its own card in More  [BLOCKED_BY_DECISION, size S, in_range]
- Android at 60f6886: SettingsScreen shows the picker in a WorkerCard after the identity card.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2192-2194
- iOS gap: Blocked by decision-61 as written; decision-71 reverses it 'for Android only'.
- Port notes: Depends on in-app-language-picker; then a Section after the identity section.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Three options in order Deutsch, English, Wie am Telefon / Use phone language under "Sprache / Language"
- [ ] #2 Switching is live on every screen including operator screens, never signs out, never touches a running shift, a material draft or the pending queue
- [ ] #3 Choosing follow-the-phone removes the override; a language set in iOS Settings shows as selected in the app and vice versa
- [ ] #4 Driven on the simulator: switch on the signed-out screen; switch with a shift running; switch with a material draft open; relaunch; change it in iOS Settings and reopen; read a re-armed reminder
- [ ] #5 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #6 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #7 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #8 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
