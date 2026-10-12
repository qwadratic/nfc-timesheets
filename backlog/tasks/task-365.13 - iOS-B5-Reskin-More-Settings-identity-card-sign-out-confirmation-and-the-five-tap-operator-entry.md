---
id: TASK-365.13
title: >-
  iOS B5: Reskin: More / Settings (identity card, sign out confirmation) and the
  five-tap operator entry
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
  - TASK-365.12
parent_task_id: TASK-365
priority: medium
ordinal: 297000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of the Blue Hour reskin (docs/ANDROID-WORKER-DESIGN.md, TASK-363). More opens with an identity card (initials + name) holding My hours (P7) and History. Sign out asks for confirmation and states the consequences. The visible operator rows on the signed-out screen and in Settings are REMOVED; the version line is the five-tap operator entry (exactly five taps, reset only on the fifth, no time window - port VersionTapGate clause for clause with its Kotlin check, android/checks/version-tap-gate-check.kt). Operator screens opened from More replace the worker scaffold (no tab bar). Wording of the version line follows decision-52.

## Items (Android evidence at 60f6886)
### more-identity-card - More opens with an identity card (initials avatar + name) holding the My hours and History rows  [PARTIAL, size S, in_range]
- Android at 60f6886: Card 1: 50dp initials circle (first letters of the first two name parts, hidden from TalkBack) + name; rows 'Meine Stunden' and, idle only, 'Verlauf'. 'Angemeldet als:' label gone. Then language card, delivery reveal, sign out, version line.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2167-2199; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:48-59
- iOS gap: Plain Form: 'Signed in as' / Name row; no avatar, no grouped links.
- Port notes: Identity row (initials circle accessibilityHidden + name, keep accessibilityLabel 'Signed in as %@'), then My hours and History links, sign out, version row. Language card blocked; delivery card not applicable.

### settings-admin-note-removed - Settings no longer prints the 'managed by your admin on the web' sentence  [PARTIAL, size S, in_range]
- Android at 60f6886: settings_admin_note is unreferenced; the same information stays in the shift help.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2167-2230; android/app/src/main/res/values/strings.xml:261
- iOS gap: iOS still prints the sentence (read).
- Port notes: Delete the Section and the key if unused; owner may prefer to keep it (worker-ui#34, sweep-inventory#8 leave it open).

### sign-out-confirmation - Sign out asks for confirmation and shows the consequences  [PORT, size S, in_range]
- Android at 60f6886: 'Abmelden' text button opens an AlertDialog titled Abmelden with settings_sign_out_note (sent shifts stay; unsent wait until you sign back in; 'Zum erneuten Anmelden brauchen Sie einen neuen Anmeldecode von Ihrer Verwaltung – der alte gilt nicht mehr.'); confirm calls signOut(), Abbrechen dismisses.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2201-2212; android/app/src/main/res/values/strings.xml:280; android/app/src/main/res/values-en/strings.xml:198
- iOS gap: One press of the bordered destructive button signs out immediately (ContentView.swift:901, read); the consequence text is only a footer and lacks the new-code sentence.
- Port notes: @State confirmingSignOut + .confirmationDialog (ShiftScreen pattern), message = existing footer key, destructive 'Sign out' + 'Cancel' (keys exist). Optionally extend the message with a new-code sentence (de+en; mention SMS as the second door).

### signin-operator-entry-behind-version-taps - Signed-out screen: visible operator row removed, version line added, five taps on it open the operator gate  [PORT, size S, in_range]
- Android at 60f6886: No operator row on the signed-out screen (signin_operator_heading deleted). Last elements: divider + app_version_line ('Installiert: %1$s (%2$d)') as a full-width min-48dp Role.Button row. Each tap runs VersionTapGate.advance(versionTapCount); taps 1-4 show nothing, the 5th sets showOperator and shows OperatorScreen (Back/system back return). Auth unchanged and owned by that screen: no ts_operator cookie -> shared code/SMS form (/auth/operator-code, /auth/operator-sms/*); cookie present -> write/test actions. No worker session, NFC or network needed for the gesture.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:175-180,303-322,390-411,425-481; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/VersionTapGate.kt:3-18; android/checks/version-tap-gate-check.kt:8-19
- iOS gap: SignInView mounts operatorSection: visible NavigationLink 'Write or test tags' + footer 'Operator? Write or test tags without signing in as a worker.' (ContentView.swift:197-204, read). No version line on this screen and no tap counting anywhere on iOS. The gate behind the door (OperatorHomeScreen, OperatorSession, CodeSignInSection) is already at parity.
- Port notes: In one change: delete operatorSection and its call (ContentView.swift:166,183-204 incl. comment), add a trailing Section with the existing key 'Installed: %@ (%@)' (hoist SettingsView.appVersion/appBuild into a shared VersionGateRow view), .contentShape(Rectangle()), min 44pt, button trait, accessibilityIdentifier; single-tap handler calls VersionTapGate.advance; 5th tap drives .navigationDestination(isPresented:) { OperatorHomeScreen() } on the existing NavigationStack. Remove the footer key from the catalogue. Update the hand-run XCUITests that find app.buttons['Write or test tags'] and the RED CASE comment at checks/localisation-check.swif

### settings-operator-entry-behind-version-taps - Signed-in More/Settings: operator row removed; the version line is the five-tap operator entry  [PARTIAL, size S, in_range]
- Android at 60f6886: No 'Tags beschreiben oder prüfen' row in Settings (settings_operator_open unreferenced; removed by 4a8ac3d after TASK-346). Last element after Sign out + divider is the same version row; 5th tap calls onOperator(), SignedInScaffold shows OperatorScreen. Worker stays signed in; Back returns to Settings; operator auth still separate. Own counter per screen.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:790-796,880,2147,2214-2229; android/checks/version-tap-gate-check.kt:14-19; android/app/src/main/res/values/strings.xml:55
- iOS gap: SettingsView still has NavigationLink 'Write or test tags' + footer (ContentView.swift:892-897, read). The version line exists with the right wording but is inert Text.
- Port notes: Delete the Section at 892-897; make the version row (912-916) the shared VersionGateRow with its own @State counter and .navigationDestination to OperatorHomeScreen inside the existing NavigationStack; keep it last. Footer sentence stays (OperatorHomeScreen.swift:66); key 'Write or test tags' becomes unused once both links are gone - delete it. Ship with the sign-in half. Simulator: type a worker code against a local API, then OperatorMockFlows.swift.

### version-tap-gate-rule - Tap gate rule: exactly five taps, reset only on the fifth, no time window  [PORT, size S, in_range]
- Android at 60f6886: Pure object: REQUIRED_TAPS = 5; advance(current) requires current in 0..4, returns (current+1,false) for taps 1-4 and (0,true) on the 5th. No timeout or other reset. Per-screen rememberSaveable counters; nothing persisted or sent.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/VersionTapGate.kt:3-18; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:176,316-320,2147,2223-2227
- iOS gap: No equivalent type or rule on iOS.
- Port notes: New Foundation-only NFCTimeSheets/NFCTimeSheets/VersionTapGate.swift: enum with requiredTaps = 5 and advance(_:) -> (tapCount, openOperator), ported clause for clause (precondition/clamp 0..<5). Per-screen @State. Do NOT use onTapGesture(count: 5). No project.pbxproj edit (file-system-synchronized group).

### version-tap-gate-check - Check pinning the gate rule and the absence of visible operator rows  [PORT, size S, in_range]
- Android at 60f6886: android/checks/version-tap-gate-check.kt compiles VersionTapGate.kt alone; asserts on TimeSheetApp.kt text (no signin_operator_heading, app_version_line exactly twice, advance(versionTapCount) exactly twice, no direct Settings RowLink) and walks the state machine (1-4 no open, 5th opens and resets, next = 1).
- Android evidence: android/checks/version-tap-gate-check.kt:8-36; android/checks/run.sh:74-80,208
- iOS gap: No iOS check for a tap gate or for absent operator links; operator-gate-check.swift pins only the cookie-derived gate.
- Port notes: Add NFCTimeSheets/checks/version-tap-gate-check.swift and register it explicitly in checks/run.sh (cat VersionTapGate.swift). Behaviour: five-tap walk. Wiring (read ContentView.swift off disk): no NavigationLink('Write or test tags'), version row in SignInView and SettingsView, advance called from both. See it red first. operator-gate-check.swift unchanged.

### operator-screen-hides-worker-tab-bar - Operator screen opened from Settings replaces the whole worker scaffold (no tab bar)  [PARTIAL, size S, in_range]
- Android at 60f6886: showOperator lives in SignedInScaffold and returns before the Scaffold composes: no bottom bar or worker tab content while the operator screen is up. Back restores Settings; worker session untouched.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:790-796,880
- iOS gap: iOS pushes OperatorHomeScreen inside the Settings tab's NavigationStack, so the worker tab bar stays visible and tappable. Session preservation and Back already match.
- Port notes: Optional, low priority: .toolbarVisibility(.hidden, for: .tabBar) on OperatorHomeScreen. Confirm with the owner first; on Android it is partly a side effect of stopping the reader.

## Rules
- Reskin means restyling what exists: P1-P7 will already have added their own rows/states as self-contained views; list in the final summary every collision you hit.
- Support German, English, large text (Dynamic Type), dark mode and Reduce Motion. Local glyphs hidden from accessibility.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 More opens with an identity card (initials avatar + name) holding the My hours and History rows
- [x] #2 Settings no longer prints the 'managed by your admin on the web' sentence
- [x] #3 Sign out asks for confirmation and shows the consequences
- [x] #4 Signed-out screen: visible operator row removed, version line added, five taps on it open the operator gate
- [x] #5 Signed-in More/Settings: operator row removed; the version line is the five-tap operator entry
- [x] #6 Tap gate rule: exactly five taps, reset only on the fifth, no time window
- [x] #7 Check pinning the gate rule and the absence of visible operator rows
- [x] #8 Operator screen opened from Settings replaces the whole worker scaffold (no tab bar)
- [x] #9 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [x] #10 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #11 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [x] #12 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [x] #13 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in de3e7c5 (branch ios-blue-hour-reskin). More: heading + ONE identity card (initials circle hidden from VoiceOver, name spoken 'Signed in as <name>', My hours, History idle-only), a quiet text Sign out that ASKS, the version line last. The 'Signed in as' header, Name row and the admin sentence are gone; no language card (decision-74) and no delivery card (decision-23).
Sign out is an ALERT (Android AlertDialog), not the confirmationDialog the port notes suggested: on iOS 26 a confirmationDialog is a narrow popover anchored to the row with no Cancel and clipped its message at the largest text size (seen in the walk). The message is the old footer plus a new-code sentence naming the admin code and, where available, the SMS code (one new key, de + en; the old footer key is retired).
OPERATOR ACCESS after B5: the visible 'Write or test tags' rows (signed-out screen and More) and both sentences are removed. The only door is the version line ('Installed: 1.0 (11)', decision-52 wording): exactly five taps (VersionTapGate, ported from VersionTapGate.kt; reset only on the fifth, no time window, not onTapGesture(count: 5)), per-screen counter, then OperatorHomeScreen - still THE gate (decision-54): no ts_operator cookie shows the shared code/SMS form, a cookie shows Write/Test. OperatorHomeScreen hides the worker tab bar (toolbarVisibility), so the operator tools replace the worker scaffold; driven with the seeded operator down to Write a tag and Test a tag (tab bar hidden on all three). The port notes marked this optional/'confirm with the owner'; the task description and criterion #8 require it, so it is done and flagged here. docs/NFC-WRITE-SETUP.md now tells operators the gesture. One deliberate difference from Kotlin: advance() treats an out-of-range count as a fresh sequence instead of throwing (a worker phone must not trap on a gesture counter); pinned.
Collisions with P1-P7: P7 (My hours moved from a Form row into the card; my-hours-check re-pinned, MyHoursView untouched), P3 (sign-out: Session.signOut and worker-scope-check unchanged, called from exactly one place; the sign-out / shared-phone / schedule-identity / delivery rig tests go through signOutFromMore), P6 (SignInView keeps DeliveryStatusRows; the version section follows the code form), B1 (History row / pop-on-shift-start kept; More is a ScrollView now so NavigationLink rows draw no second chevron).
Hand-run XCUITests (FinishReportedCardUITests, SmsDoorVisibilityUITests, WriteTagRestartUITests) now open the gate with the version line; they target a stub server and were compiled with the rig build but NOT run. Not proven: VoiceOver itself.
Checks: version-tap-gate-check (rule + initials + wiring, in run.sh) and worker-reskin-check section 3e, each pin reproduced RED by mutation (requiredTaps 4, no reset on the fifth, trusting an out-of-range count, a Date in the row, the row title back, a missing version line, onTapGesture(count: 5), tab bar left visible, three initials, the retired key back, sign-out on one press, the admin sentence back, a language picker, German losing the SMS door, confirmationDialog back).
Rig: signOutFromMore / openOperatorGate helpers; rig.sh new-code O (seeded operator); walks testB5MoreIdentityCardAndSignOutDialog (all five combos), testB5VersionLineFiveTapsOpenTheOperatorGate (five combos; four taps with a 12 s pause open nothing, fifth opens, no tab bar, Back keeps the worker signed in, next sequence resets), testB5SignedOutVersionLineAndGate (light-en-m, dark-de-xxxl, light-en-xxxl), testB5OperatorToolsKeepTheTabBarHidden (light-en-m, dark-en-m). Regression walks PASS: signin, p3 (signout, b-signin, b-same-place, b-elsewhere, a-returns, session-rejected, replaced, swipe-delete), p4-identity, p6-signin, p1-material (34/34 lines).
Evidence: /private/tmp/claude-501/-Users-gerhardgustav-Desktop-ai-automations-hoiv-cleaning-timesheets/bae0f966-d0f9-4618-a839-103c98835ae8/scratchpad/rig-reskin/shots (<combo>-b5-01..b5-09).
<!-- SECTION:NOTES:END -->
