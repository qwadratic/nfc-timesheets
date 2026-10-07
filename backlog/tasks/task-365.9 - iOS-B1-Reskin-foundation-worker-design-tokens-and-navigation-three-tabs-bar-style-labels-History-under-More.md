---
id: TASK-365.9
title: >-
  iOS B1: Reskin foundation: worker design tokens and navigation (three tabs,
  bar style, labels, History under More)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - reskin
dependencies:
  - TASK-365.8
parent_task_id: TASK-365
priority: medium
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of the Blue Hour reskin (docs/ANDROID-WORKER-DESIGN.md, TASK-363). Shared tokens first (a small WorkerStyle.swift: card modifier, primary ButtonStyle, typography), then the three-tab bar (Shift/Schicht, Materials, More/Mehr). Agree the button target with the owner first (accent vs Android's inverse-filled): it is a design call, not an engineering one. SF Symbols instead of Android's Canvas glyphs; keep Dynamic Type.

## Items (Android evidence at 60f6886)
### worker-surface-tokens - Shared worker visual language: 18dp cards, 16dp inverse-filled buttons, heavier titles  [PARTIAL, size M, in_range]
- Android at 60f6886: WorkerCard (18dp), inverseSurface primary buttons min 56dp, shape/typography overrides, locally drawn glyphs hidden from accessibility, no idle animation.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/Theme.kt:77-96,165-276; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerVisuals.kt:31-97
- iOS gap: Stock List/Form chrome, one-off card helper in ShiftScreen, AccentColor buttons; no shared tokens.
- Port notes: Design pass after the functional items: small WorkerStyle.swift (card modifier, primary ButtonStyle), SF Symbols instead of Canvas glyphs, keep Dynamic Type. Agree the target (accent vs inverse buttons) with the owner first.

### worker-nav-three-tabs - Bottom navigation is always three destinations (Shift, Materials, More); History is never a tab  [PARTIAL, size S, in_range]
- Android at 60f6886: tabs = ShiftSignal.visibleTabs(...).filterNot HISTORY (TimeSheetApp.kt:807, read), so idle and running show three tabs. Selection saved by NAME, falling back to Shift; per-tab state in a SaveableStateHolder; Materials badge unchanged; no top app bar.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:790-813,831-892; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/ShiftSignal.kt:64-78
- iOS gap: iOS shows four tabs when idle (Log, Materials, History, Settings), three while a shift runs. Badge exists.
- Port notes: Filter .history out of the ForEach in ContentView (leave ShiftSignal.visibleTabs/AppTab so shift-signal-check:113-115 stays green), add TabView(selection:) with stable tags at the same time, assert in a check that no History tabItem is mounted. Keep the MigrationReceipt .task/.sheet pair on the TabView. Labels and History's new home are separate items.

### nav-bar-style-and-icons - Navigation bar restyle: rounded top, dark selection pill, hand-drawn icons  [PARTIAL, size S, in_range]
- Android at 60f6886: NavigationBar with 24dp top corners, inverseSurface indicator, Canvas icons (clock, box, three dots).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:834-869; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerNavIcon.kt:15-36
- iOS gap: Stock tab bar with SF Symbols wave.3.right, shippingbox, list.bullet, gear.
- Port notes: Keep the system TabView; only swap symbols to match meaning (Shift -> clock, More -> ellipsis).

### tab-labels-shift-and-more - Tab labels renamed: Schicht/Shift and Mehr/More  [PORT, size S, in_range]
- Android at 60f6886: tabLabel(): LOG = nav_shift, SETTINGS = nav_more; tab_log/tab_settings dead. Heading inside More stays settings_title.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:866,887-892; android/app/src/main/res/values/strings.xml:618-619; android/app/src/main/res/values-en/strings.xml:489-490
- iOS gap: Tab items read 'Log' (Erfassen) and 'Settings' (Einstellungen).
- Port notes: Swap the two Label titles; add keys 'Shift' (de 'Schicht') and 'More' (de 'Mehr'); keep 'Settings' for the navigationTitle; remove 'Log'. localisation-check's extractor does not match Label(...): extend it or verify by hand.

### history-under-more - Local History is a row under More, shown only while no shift is open  [PARTIAL, size S, in_range]
- Android at 60f6886: More's identity card shows 'Verlauf' only when log.open == null; it opens the unchanged HistoryScreen under a Back text button; dismissed if a shift starts.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2101-2143,2156-2165,2186-2189
- iOS gap: HistoryView exists with equivalent content but is a tab; no History row in Settings.
- Port notes: SettingsView: NavigationLink('History') { HistoryView() } only when the worker has no open shift (worker-scoped). Remove HistoryView's own NavigationStack (ContentView.swift:839) when pushed. Pop it if a shift starts. Keep swipe-to-delete (iOS-only) deliberately. Key exists.

### tap-on-any-tab-jumps-to-shift - A tap arriving on Materials or More switches to the Shift tab and is handled once  [PARTIAL, size S, in_range]
- Android at 60f6886: The pending-tap consumer lives in SignedInScaffold: when pendingTap is non-null it selects the Shift tab, then consumePendingTap(). Driven: a tap from Materials/More returns to Shift and opens then closes exactly one row. While the operator screen shows, the tap stays parked.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:790-796,815-822; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:144-167; docs/android-worker-verification.md:39
- iOS gap: iOS consumes the tap only inside LogView and TabView has no selection binding, so a universal-link tap on another tab never brings the worker to the shift screen. Whether LogView's onChange fires for a non-selected tab was not established by any source.
- Port notes: ContentView: @State selection: AppTab = .log, TabView(selection:) with .tag, and .onChange(of: inbox.pendingLocationId) setting selection = .log when non-nil. Keep take()/handleTap in LogView as the single consumer (tap-inbox-check, shift-signal-check). Fall back to .log if the selection is History when the lock removes it. Simulator: --ts-demo-tap only covers cold launch; add a DEBUG hook or accept device-only verification and say so.

## Rules
- Reskin means restyling what exists: P1-P7 will already have added their own rows/states as self-contained views; list in the final summary every collision you hit.
- Support German, English, large text (Dynamic Type), dark mode and Reduce Motion. Local glyphs hidden from accessibility.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Shared worker visual language: 18dp cards, 16dp inverse-filled buttons, heavier titles
- [ ] #2 Bottom navigation is always three destinations (Shift, Materials, More); History is never a tab
- [ ] #3 Navigation bar restyle: rounded top, dark selection pill, hand-drawn icons
- [ ] #4 Tab labels renamed: Schicht/Shift and Mehr/More
- [ ] #5 Local History is a row under More, shown only while no shift is open
- [ ] #6 A tap arriving on Materials or More switches to the Shift tab and is handled once
- [ ] #7 Screen-by-screen walk on the simulator in light, dark and the largest Dynamic Type size, de and en, with screenshots attached to the final summary
- [ ] #8 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #9 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #10 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #11 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
