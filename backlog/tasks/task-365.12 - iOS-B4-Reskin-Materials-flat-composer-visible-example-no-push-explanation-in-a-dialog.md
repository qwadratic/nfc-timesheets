---
id: TASK-365.12
title: >-
  iOS B4: Reskin: Materials (flat composer, visible example, no-push explanation
  in a dialog)
status: In Progress
assignee: []
created_date: '2026-10-07 12:22'
updated_date: '2026-10-12 22:55'
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
- [x] #1 Materials composer restyle: flat block with illustration, full-width button, visible saved line
- [x] #2 Materials no-push explanation: one short line plus a 'So erhalten Sie Rückmeldung' dialog
- [x] #3 Materials field shows a short visible example
- [x] #4 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [x] #5 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #6 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #7 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #8 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in a910ad2 (branch ios-blue-hour-reskin). Page heading in the shared title style (empty inline bar, like idle/running). Composer = ONE flat block on the page: 'Ask for something' + a fixed 64 pt SF Symbol mark (hidden from VoiceOver; no Canvas port, as the port notes say), the outlined 2-8 line field with the VISIBLE example ('For example: 2 mops, glass cleaner'), the building context, ONE full-width inverse-filled Send (shared 56 pt/16 pt style), a visible 'Request saved...' line that goes when the NEXT request is typed (not when the submit empties the field), ONE short always-visible line 'Check updates here. No push notifications.' and a 'How updates work' button whose alert holds the two existing long explanations (with / without a building). decision-23: nothing on the screen promises a notification (pinned: every literal that mentions a notification must say there is none). Arrivals and both request rows are worker cards.
Localisation bugs fixed alongside: statusText returned String into Label (verbatim initialiser => English on a German phone) - now a LocalizedStringKey with six catalogue keys in Android's German; the building context 'For <name>' had the same defect (two literal Texts now); the spoken confirmation is String(localized:). The long VoiceOver hint is gone (the example is visible; Android replaced it too).
Deviations: SF Symbol shippingbox stands in for Android's drawn supplies picture; request rows are cards (Android uses divider rows) for consistency with ShiftRow. New strings both languages: For example..., Check updates here..., How updates work, Request saved..., Waiting for the office, Approved - not ordered yet, Ordered, Collected, Not approved, Status unknown - ask your admin.
Collisions with P1-P7: P1 (Zones.materialContext: untouched, still pinned; p1-material walk PASS), P3 (worker-scope-check still pins MaterialsView's scoped reads), P7/P4/P5/P6: none. Not proven: VoiceOver itself (the spoken labels are pinned, the rig cannot run VoiceOver).
Checks: worker-reskin-check section 3d; each pin reproduced RED by mutating the source (example dropped, borderedProminent back, statusText back to String, a Section in the composer, a promised notification, the long sentence printed, the saved line cleared by the submit, a bare English announcement, lineLimit 1, an English entry lost, German drifting from Android).
Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-reskin/shots (light-en-m-/dark-en-m-/light-de-m-/dark-de-xxxl-/light-en-xxxl- b4-01..b4-07), driven by ops/ios-rig/reskin-walk.sh (testB4MaterialsComposerAndDialog on all five, testB4MaterialsForTheBuilding on light-en-m, dark-de-xxxl, light-en-xxxl).
<!-- SECTION:NOTES:END -->
