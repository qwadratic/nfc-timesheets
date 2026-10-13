---
id: TASK-335
title: 'Android: hide pre-auth operator entry behind five version taps'
status: Done
assignee: []
created_date: '2026-09-19 15:21'
updated_date: '2026-09-19 17:56'
labels: []
dependencies: []
references:
  - >-
    backlog/decisions/decision-54 -
    Zone-creation-and-binding-move-to-the-operator-app-zones-may-exist-unbound-the-operator-interface-is-gated-behind-sign-in-one-shared-code-form-serves-every-login.md
  - >-
    backlog/decisions/decision-52 -
    App-version-display-uses-one-shared-wording-across-Android-and-iOS-not-a-shared-version-number.md
modified_files:
  - >-
    android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/VersionTapGate.kt
  - >-
    android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt
  - android/app/src/main/res/values/strings.xml
  - android/app/src/main/res/values-en/strings.xml
  - android/checks/version-tap-gate-check.kt
  - android/checks/run.sh
  - android/.gitignore
type: enhancement
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The signed-out screen exposes specialist operator tooling as a normal visible row. Replace that pre-auth row with the existing localized app-version text and open the same gated operator screen only after five taps, while leaving the signed-in Settings operator entry unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The signed-out screen no longer shows a visible operator entry.
- [x] #2 The signed-out screen shows the localized app-version line.
- [x] #3 The first four version taps do not navigate; the fifth opens the existing operator sign-in screen and resets the counter.
- [x] #4 The signed-in Settings operator entry remains unchanged.
- [x] #5 The version row has a usable touch target and focused checks cover the five-tap transition.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extract a small Android-free five-tap gate and cover it with a dedicated check. 2. Replace the pre-auth operator row with an interactive localized version line; leave signed-in Settings unchanged. 3. Run focused Android checks, resource parity, branding validation, and a five-axis diff review; record the managed-environment build boundary.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented the clarified scope: the visible pre-auth operator row is removed; the localized version row now drives a five-tap gate into the existing OperatorScreen; the signed-in Settings operator row remains unchanged. Added a dedicated Android-free state-transition and wiring check plus ignored its generated output. Validation: version-tap-gate-check compiled and passed; German/English string-key parity passed with 333 keys; Android Studio Gradle sync and debug build succeeded; node ops/check-branding.mjs passed; git diff --check passed. The owner manually tested the installed app on the Pixel 9 API 36 emulator and reported the app and new interaction working. A later ADB readback was unavailable because the emulator had already disconnected. Review found no functional, authentication, localization, touch-target, security, or performance defect.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved the pre-auth operator entry behind five taps on the localized app-version row, preserved the signed-in Settings entry, and added a focused state-transition/wiring check. Verified by successful Android Studio debug build, focused checks, localization parity, branding and diff gates, plus the owner manual emulator test.
<!-- SECTION:FINAL_SUMMARY:END -->
