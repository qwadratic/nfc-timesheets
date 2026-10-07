---
id: TASK-365.12
title: >-
  iOS B4: Reskin: Materials (flat composer, visible example, no-push explanation
  in a dialog)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - reskin
dependencies:
  - TASK-365.11
parent_task_id: TASK-365
priority: medium
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of the Blue Hour reskin (docs/ANDROID-WORKER-DESIGN.md, TASK-363). Flat composer block with a small illustration, full-width button, visible saved line, one short no-push line plus a "How you get an answer" dialog. decision-23: there is NO push - never promise a notification.

## Items (Android evidence at 60f6886)
### materials-composer-redesign - Materials composer restyle: flat block with illustration, full-width button, visible saved line  [PARTIAL, size S, in_range]
- Android at 60f6886: Heading + 64dp supplies illustration; outlined field 2-8 lines with counter; 'Für <building>' context; full-width dark 'Anfrage senden'; visible 'Anfrage gespeichert...' line; arrivals as cards. Submit/queue logic unchanged.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1831-2012; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerVisuals.kt:42-97
- iOS gap: Functionally identical; presentation differs (stock List sections, default button, no illustration, saved confirmation only as a VoiceOver announcement).
- Port notes: Optional polish in MaterialsView.compose: title + SF Symbol, full-width .borderedProminent, visible saved line (sentence exists). No Canvas port. sweep-commits#48 notes statusText returns unlocalized literals - fix alongside.

### materials-no-push-details-dialog - Materials no-push explanation: one short line plus a 'So erhalten Sie Rückmeldung' dialog  [PARTIAL, size S, in_range]
- Android at 60f6886: Under the send button: 'Status hier prüfen. Keine Push-Mitteilungen.' and a text button opening an alert with the unchanged long paragraph.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1960-1972; android/app/src/main/res/values/strings.xml:675-676
- iOS gap: iOS prints the full explanation permanently as the section footer (two variants).
- Port notes: Short Text + Button('How updates work') presenting the existing long key(s). New de+en keys 'Check updates here. No push notifications.' and 'How updates work'/'So erhalten Sie Rückmeldung'. Keep the short note always visible (decision-23).

### materials-example-supporting-text - Materials field shows a short visible example  [PARTIAL, size S, in_range]
- Android at 60f6886: Supporting text worker_material_example 'Zum Beispiel: 2 Mopps, Glasreiniger' replaces the long material_input_hint.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1903-1920; android/app/src/main/res/values/strings.xml:358,674
- iOS gap: The old long wording exists only as a VoiceOver hint; a sighted worker sees no example.
- Port notes: Caption Text under the TextField: 'For example: 2 mops, glass cleaner' (de above); shorten or keep the hint.

## Rules
- Reskin means restyling what exists: P1-P7 will already have added their own rows/states as self-contained views; list in the final summary every collision you hit.
- Support German, English, large text (Dynamic Type), dark mode and Reduce Motion. Local glyphs hidden from accessibility.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Materials composer restyle: flat block with illustration, full-width button, visible saved line
- [ ] #2 Materials no-push explanation: one short line plus a 'So erhalten Sie Rückmeldung' dialog
- [ ] #3 Materials field shows a short visible example
- [ ] #4 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [ ] #5 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #6 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #7 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #8 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
