---
id: TASK-365.18
title: 'iOS: deferred worker parity debt (pre-existing gaps, not scheduled)'
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - deferred
dependencies: []
parent_task_id: TASK-365
priority: low
ordinal: 302000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gaps that PREDATE PRs 3-7 or were consciously deferred; each deserves its own task when someone takes it. Related: TASK-362 (Android: recover from server-rejected unknown tag shifts), TASK-327 (fallback language, owner), TASK-188 (iOS names the renameable API host), TASK-44 (Sentry DSN).

### worker-scan-serial-lookup - Worker scan resolves a URL-less adopted tag by hardware serial through roster zones  [PARTIAL, size S, pre_existing]
- Android at 60f6886: Both worker read paths resolve: tag URL -> Zones.zonePlaceIdForSerial(uid, cached zones) (tag_serial published only for verified zones) -> KnownTags (empty). The zone UUID is posted; the serial never travels.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/WorkerTagReader.kt:29-39; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/ScanActivity.kt:142-188; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/Zones.kt:44-47
- iOS gap: TapScanner resolves URL cards only and says it has no serial fallback because a worker phone has no zone list - true only because iOS drops roster.zones. Operator probe already matches serials.
- Port notes: Needs worker-roster-zone-cache. In TapScanner.process, when no URL resolved, read the identifier like TagReaderProbe.identifier(of:) and resolve via Zones.zonePlaceIdForSerial; feed inbox.accept. In-app scan only (no universal link without a URL). Pure function vectors in zones-check. Low priority: no adopted cards known deployed.

### rejected-unknown-tag-shift - TASK-362: a server-rejected unknown tag still becomes a local running shift (open on Android, present on iOS)  [PARTIAL, size S, pre_existing]
- Android at 60f6886: Open defect (TASK-362 To Do). A well-formed unknown UUID creates a local open row; push gets terminal 422 unknown_location/tag_unbound, row blocked. Android HEAD at least shows 'Not confirmed yet', the rejection sentence and a 'needs your office' row. Manual Stop is online-only and answers 404 unknown_shift, leaving the row open (the trap). No recovery UI.
- Android evidence: backlog/tasks/task-362 - Android-recover-from-server-rejected-unknown-tag-shifts.md:1-30; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:715-750,863-893; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/ApiFailure.kt:69-80
- iOS gap: Same root defect on iOS. No unfinishable-shift trap (manual stop closes locally first), but worse while running: ShiftScreen shows 'Clocked in' with no rejection; the red sentence appears only on the closed row.
- Port notes: No Android fix to port. Visibility comes with the pending-confirmation and sync-error items. Keep iOS local-first manual STOP. Do not invent a recovery flow or auto-delete blocked rows (TASK-362 AC). Track under TASK-362 or a sibling.

### manual-start-online-with-inline-refusals - Manual start is online on Android: refusal shown in the dialog, no local row on failure  [PARTIAL, size M, pre_existing]
- Android at 60f6886: manualOpen awaits POST /shifts/open; only success writes a row (adopt, synced). Any ApiFailure leaves the store untouched and renders under the list (err_zone_unverified, err_tag_unbound, err_unknown_location, err_shift_already_open, err_network); dialog stays open. No offline manual start.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:796-856; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1364-1372,1411-1417
- iOS gap: iOS manual start is local-first by design (same handleTap, one flag): row, running screen and signals exist before the server answers; a refusal lands only as syncError on the row. Missing vs Android: in-sheet refusal and no-row-on-refusal. Divergence existed at 8aafbf1.
- Port notes: Owner choice. (a) Android model: dedicated async start awaiting ShiftFlowAPI.open, insert an already-synced Shift like adoptServerOpenShift on success, show failure.workerMessage in the sheet; must not route through handleTap (ordering pinned as text). (b) Keep local-first and rely on running-screen-pending-confirmation + running-screen-sync-error-and-refresh. Keep local-first manual STOP either way.

### background-queue-delivery - Queued shifts are delivered in the background when a network appears  [PORT, size L, pre_existing]
- Android at 60f6886: SyncScheduler.ensure schedules a persisted network-constrained JobScheduler job after local writes; survives reboot; isScheduled drives the delivery sentences. Since TASK-225 (pre-range).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/sync/SyncScheduler.kt:112-161; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:727-750; android/app/src/main/AndroidManifest.xml:244-247
- iOS gap: iOS pushes only on tap, pull-to-refresh and Log tab appearance; Sync.swift names BGAppRefreshTask as the upgrade path.
- Port notes: Separate task, not part of the UI port: BGTaskScheduler calling syncPending; needs the Background Modes capability (pbxproj, owner) and BGTaskSchedulerPermittedIdentifiers. iOS gives no delivery guarantee, so copy must not promise it.

### pending-heartbeat-headers - X-Pending-Shifts / X-Pending-Blocked / X-Pending-Oldest heartbeat headers on worker requests  [PORT, size M, pre_existing]
- Android at 60f6886: Every worker-jar request carries the two counts and, when pending, the oldest unsent start; also X-Client: android/<version>. Operator client sends none. Server stores them per worker, fire-and-forget.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/net/Api.kt:557-559,601-631; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/data/ShiftStore.kt:245; server/lib/phones.js:53-88
- iOS gap: iOS sets only X-App-Key; the admin cannot tell an iPhone holding unsent shifts from an idle one. Predates the range.
- Port notes: After PendingWork.swift: a cached summary read by apiGet/apiPost through a static closure (API.swift stays Foundation-only); never query SwiftData from transport; never from sendOperator; header failures never fail a request. Check for formatting and 'Oldest omitted when nothing pending'.

### worker-scan-diagnostics - Worker scan reports what an unrecognised card contained  [PARTIAL, size S, pre_existing]
- Android at 60f6886: ScanActivity shows 'no web address' or 'address X is not for host Y' with technologies and UID.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/ScanActivity.kt:184-203
- iOS gap: iOS collapses every non-matching read into one sentence with no host/UID.
- Port notes: Low priority: extend TapScanner.Outcome.unrecognised with (uri, uid) and append to the alert; share host-mismatch logic with unreadable-card-diagnosis.

### sentry-live-telemetry-on-device - Android ships live Sentry; iOS telemetry is compiled out and its trace targets name the wrong host  [PARTIAL, size S, pre_existing]
- Android at 60f6886: sentry-android linked, DSN in BuildConfig, manual init with samplers and Scrub hooks (decision-70, pre-range).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/Telemetry.kt:24-59; android/app/build.gradle.kts:104,181
- iOS gap: The iOS layer is written but the sentry-cocoa package is not linked, so nothing is sent. Telemetry.swift:97-98 sets tracePropagationTargets/failedRequestTargets to [TagLink.host] (read) - the TAG host, while requests go to Branding.apiHost.
- Port notes: Linking the package is OWNER-ONLY (pbxproj). Agent-fixable now: change both targets to [Branding.apiHost] (accessor, not a literal - check-branding forbids the literal) and add a text assertion.

### live-activity-pending-state - Persistent lock-screen signal can express 'not confirmed yet'  [PORT, size S, in_range]
- Android at 60f6886: The single ongoing notification picks title/text/BigText by pending > overdue > running and is re-posted on every arm.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/ShiftSignals.kt:91-148
- iOS gap: iOS equivalents are the wordless badge and the Live Activity, whose ContentState carries only 'overdue' and which is inert until the owner adds the widget extension target.
- Port notes: Add 'pendingConfirmation' to ShiftActivityAttributes.ContentState and pass it in LiveActivityController.start; update docs/LIVE-ACTIVITY-SETUP.md:59-60 so the owner-built widget renders it in words. No project.pbxproj edit; invisible until the owner adds the extension. Low priority.

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
- [ ] #1 Split into real tasks before any of it is started
- [ ] #2 Each item either scheduled with its own acceptance criteria or closed Wont Do with a reason
<!-- AC:END -->
