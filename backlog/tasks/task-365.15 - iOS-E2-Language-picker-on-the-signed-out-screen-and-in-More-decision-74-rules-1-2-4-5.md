---
id: TASK-365.15
title: >-
  iOS E2: Language picker on the signed-out screen and in More (decision-74
  rules 1, 2, 4, 5)
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
- [x] #1 Three options in order Deutsch, English, Wie am Telefon / Use phone language under "Sprache / Language"
- [x] #2 Switching is live on every screen including operator screens, never signs out, never touches a running shift, a material draft or the pending queue
- [x] #3 Choosing follow-the-phone removes the override; a language set in iOS Settings shows as selected in the app and vice versa
- [x] #4 Driven on the simulator: switch on the signed-out screen; switch with a shift running; switch with a material draft open; relaunch; change it in iOS Settings and reopen; read a re-armed reminder
- [x] #5 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #6 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #7 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #8 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 3a6ba15 (branch ios-language). LanguagePicker.swift: ONE view, two places, both Android's: a Section under the brand block of SignInView (before the delivery rows and the code form) and its own workerCard() after the identity card in SettingsView. Title Sprache / Language, options Deutsch, English, Wie am Telefon / Use phone language IN THAT ORDER (AppLanguage.options), Android's words verbatim from strings.xml (pinned in both languages), the chosen option filled with WorkerInverse/WorkerOnInverse on a WorkerStyle.soft track, 48 pt minimum, stacked one per line at the accessibility text sizes, exposed as one VoiceOver group with .isSelected on the chosen option (iOS has no radio role) and identifiers language-de / -en / -system. A tap calls AppLanguageModel.select and nothing else (the check reads the file for Session, ModelContext, Shift, MaterialStore, signOut, syncPending, URLSession, UserDefaults...).

DRIVEN (criterion #4; WorkerRigLanguageUITests through reskin-walk.sh, phone en and phone de - the German phone choosing English is the direction a lookup that silently falls back to the process language would fail, and it passes): the signed-out switch is live (same screen, other language, picker re-worded, 'Deutsch'/'English' unchanged); follow-the-phone gives the phone's language back and removes the value; relaunch keeps the choice; signing in while it is chosen keeps it (tab bar in the chosen language); with a shift running the server still has exactly ONE open shift and the same running screen comes back re-worded (rig driver check); with a material draft open the draft is still in the field after the switch and the server has 0 material requests; the operator gate is in the chosen language; iOS Settings > Apps > NFCTimeSheets > Language shows an in-app choice (value 'German', checkmark on Deutsch) and choosing English/Default or Deutsch THERE is what the app shows and selects when opened again with no launch arguments (Default removes the override -> 'Use phone language' selected). One value, not two: criterion #3. 'Read a re-armed reminder' is E3's (TASK-365.16, driven in L6, from the phone's string-resolution log: see there). Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-lang/shots (<combo>-l1-*, l2-*, l3-*, l4-*, l5-*, and b5-01-more with the card).

Collisions: the reskin check's 'More has no language picker' pin became 'the ONE shared LanguagePicker is its own card after the identity card' (More's order pinned: heading, identity card, language card, divider, Sign out, divider, version line); WorkerRigReskinUITests' 'no language picker' assertion is now the three buttons being there after History. The driver reskin-walk.sh takes CLASS=... and gained the server assertions check-open-shift / check-no-material-request. Debug and Release builds SUCCEEDED, checks/run.sh green, node ops/check-branding.mjs 14 ok / no TODO / OK, no edit to project.pbxproj or the entitlement. New check pins each reproduced RED by mutation (the tap signing out, the card removed from More, the picker after the sign-in form, Android's third-option German drifting, the options reordered).
<!-- SECTION:NOTES:END -->
