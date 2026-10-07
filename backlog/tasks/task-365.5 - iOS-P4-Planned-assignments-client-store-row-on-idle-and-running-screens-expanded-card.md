---
id: TASK-365.5
title: >-
  iOS P4: Planned assignments: client, store, row on idle and running screens,
  expanded card
status: To Do
assignee: []
created_date: '2026-10-07 12:21'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.4
parent_task_id: TASK-365
priority: medium
ordinal: 289000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The worker sees the next planned assignment as a collapsed row (View/Close) on the idle list and the running screen, expanded into a 'My schedule' card with all upcoming assignments, loading/empty/offline/error states and a refresh control. Display only: never read by tap handling, sync, signals or navigation.
## Decision to record FIRST (decision-78)
Record decision-78: the iOS worker app shows the signed-in worker's planned assignments, read-only (amends decision-73 / docs/product-launch-and-scheduling.md:36)?
Context: decision-73 (accepted, body empty) delegates to docs/product-launch-and-scheduling.md, which says line 36 'iOS scheduling is not added in this iteration; its existing NFC behavior is unaffected' - a scope note, not a prohibition. Android shows GET /me/schedule (TASK-345/363). Proposed rule: iOS shows the same data, display only - planned_shifts never join payroll, P&L, NFC eligibility, sync or signals; no new tab, no push or reminder; failures never affect clock-in; collapsed 'Next planned assignment' row on idle and running screens, expanded 'My schedule' card; dates in Europe/Vienna; identity from the session. No server change (route exists, server/routes/schedule.js:171). Must be recorded
Recommendation (planned as accepted): Accept as written; owner priority C is exactly this feature. Planned as accepted.

## Items (Android evidence at 60f6886)
### me-schedule-endpoint-client - Client and wire type for GET /me/schedule (the worker's planned assignments)  [PORT, size S, in_range]
- Android at 60f6886: Api.mySchedule(): GET /me/schedule with X-App-Key + ts_worker cookie, no params (identity from session; ?worker_id ignored). 200 {assignments:[...]}: session worker's uncancelled planned_shifts with ends_at > now and starts_at < now + 31 days, ordered by starts_at, max 200, tenant-scoped by RLS. Android decodes id, location_name, starts_at, ends_at (required) and note (default ''), ignores the rest. 401 -> signed out; transport -> status 0; 404/500 -> ApiFailure(status).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/net/Api.kt:482-486; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/Wire.kt:77-83,316-323; server/routes/schedule.js:23-31,171
- iOS gap: No /me/schedule call, type or schedule concept anywhere in the iOS tree.
- Port notes: API.swift: struct WireScheduleAssignment: Decodable, Identifiable, Equatable {id, locationName, startsAt, endsAt, note} with explicit CodingKeys, note decodeIfPresent ?? ''; envelope {assignments}; enum ScheduleAPI { static func mine() } via apiGet (worker cookie jar, never OperatorAPI). Do not decode location_id. Decode vector in checks/tag-link-check.swift (extra keys, .000Z and whole-second timestamps, note absent, empty list).

### schedule-load-lifecycle - Schedule is fetched fresh on every shift-screen resume, never cached, guarded against stale answers  [PORT, size S, in_range]
- Android at 60f6886: loadSchedule() runs from a LifecycleResumeEffect on the Shift tab and from refresh/retry: no-op unless signed in; bumps a request counter, sets Loading (previous list dropped), publishes Loaded/Failed(offline = status 0) only if still the latest request and still signed in; CancellationException rethrown. Held in the ViewModel only; never read by tap handling or refresh().
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:877,900-905; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:124-128,195-197,1017-1039
- iOS gap: No schedule state and no trigger.
- Port notes: In-memory enum ScheduleState {loading, loaded([..]), failed(offline: Bool)} (Equatable, Foundation-only reducer for a check). Load via its own .task(id: worker.id) and on scenePhase .active as a SEPARATE Task - never inside refresh() ahead of syncPending/arm, never awaited by handleTap. Request token; no SwiftData/UserDefaults and no invalidateCachesIfUpdated line.

### schedule-reset-on-identity-change - Schedule state is invalidated on sign-out, a 401 and a change of worker  [PORT, size S, in_range]
- Android at 60f6886: signOut(), dropToSignedOut() and adopt() of a DIFFERENT worker bump scheduleRequest and reset to Loading; re-confirming the SAME cached worker does not reset. Driven A->B->A: B saw none of A's assignments.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:566-567,588-595,1053-1055; docs/product-launch-verification.md:55,89
- iOS gap: State does not exist. Note Session.restore() can replace a cached worker with a different one without passing through signedOut, keeping LogView's @State.
- Port notes: Key the load on .task(id: worker.id), set .loading first, compare a token/worker id before publishing. If an @Observable store beside 'materials' is used it survives sign-out and must be reset explicitly (MaterialStore.adopted(by:) is the precedent). Check vectors: stale token ignored, different worker resets, same worker keeps.

### schedule-vienna-time-zone - Schedule dates and times are rendered in Europe/Vienna, not the phone's zone  [PORT, size S, pre_existing]
- Android at 60f6886: viennaDate()/viennaTime() format with ZoneId Europe/Vienna; helpers predate the range (TASK-189, My hours) and were only made internal in b7eca84.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:2472-2493; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:133
- iOS gap: No zone-pinned formatting anywhere on iOS.
- Port notes: Small Foundation-only helper (e.g. BusinessTime/ViennaTime.swift): TimeZone(identifier: 'Europe/Vienna'), date/time FormatStyles, sameDay via a Calendar in that zone; reuse for My hours. checks/schedule-check.swift: 22:00-02:00 cross-day, DST boundary, device TZ not Vienna.

### schedule-time-line-format - Assignment time line: compact same-day form, long form across midnight  [PORT, size S, in_range]
- Android at 60f6886: Same Vienna day: schedule_same_day '%1$s · %2$s–%3$s' (unspaced en dash); otherwise schedule_when '%1$s, %2$s – %3$s, %4$s'. Medium date, short time. Same-day test compares the two formatted dates (end at 00:00 = cross-day). No relative words, weekday or duration.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:132-140,174-177; android/app/src/main/res/values/strings.xml:638,645; android/app/src/main/res/values-en/strings.xml:509,516
- iOS gap: No formatter for a planned window; neither the three- nor the four-argument key exists.
- Port notes: Two non-positional keys: '%@ · %@–%@' (de '%1$@ · %2$@–%3$@') and '%@, %@ – %@, %@'. OS locale (not AppLanguage). Put the same-day decision in the Foundation-only schedule file with check vectors.

### schedule-next-assignment-row-idle - Idle home shows a collapsed 'Nächster geplanter Einsatz' row with Ansehen/Schließen  [PORT, size M, in_range]
- Android at 60f6886: WorkerScheduleSummary after the start card, delivery rows and NFC banner, before Recent: divider + full-width min-48dp text button, label worker_planned left, worker_show/worker_hide right. Collapsed and Loaded with >= 1 row: first assignment's building (titleMedium) and time line. Collapsed while loading/failed/empty: nothing under the row. expanded is rememberSaveable; the assignment is not a link; no tab, no reminder.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:158-181; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1026; android/app/src/main/res/values/strings.xml:669-671
- iOS gap: idleList has no schedule content.
- Port notes: New ScheduleSummary view (state + retry, @State expanded) as a Section between the start action and Recent; spell the action in words (Button row, not a bare chevron). New de+en keys 'Next planned assignment'/'Nächster geplanter Einsatz', 'View'/'Ansehen', 'Close'/'Schließen'. Simulator: add DEBUG canned schedule flows (ScheduleFlowAPI seam in ShiftMockFlows style: loaded/empty/offline/multi-day).

### schedule-row-on-running-screen - The same planned-assignment row is shown on the running-shift screen  [PORT, size S, in_range]
- Android at 60f6886: ShiftRunningScreen renders WorkerScheduleSummary after the notifications-off card and before help, in on-blue ink; same state and retry. Label stays 'Next planned assignment' even if the first row is in progress.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:956,1104,1313; server/routes/schedule.js:26
- iOS gap: ShiftScreen takes nothing about a schedule.
- Port notes: Add schedule state + retry closure to ShiftScreen, insert before helpCard inside the card() helper. Keep expanded in @State so the minute TimelineView tick does not collapse it. No new strings.

### schedule-expanded-card - Expanded 'Meine Einsätze' card: first assignment, 'all upcoming' toggle, per-row building, time and note  [PORT, size M, in_range]
- Android at 60f6886: ScheduleCard: heading schedule_title + refresh icon, caption worker_schedule_note 'Geplant · Arbeitszeit separat erfassen', then state body. Loaded non-empty: ONLY the first assignment; with more than one a toggle 'Alle kommenden Einsätze' / 'Weniger anzeigen' lists all (up to 200) with dividers. Row: building, time line, note when not blank (full text). show-all flag resets when state changes. Server order; no grouping or in-progress badge.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:104-156,183-195; android/app/src/main/res/values/strings.xml:630,639-640,647; android/app/src/main/res/values-en/strings.xml:501,510-511,518
- iOS gap: No such card.
- Port notes: Private ScheduleCard in the same file with @State showAll reset via .onChange(of: state). New de+en keys 'My schedule'/'Meine Einsätze', 'Planned · Clock in separately', 'All upcoming assignments', 'Show less'. Do NOT port schedule_explainer (dead). Keep Einsatz (plan) vs Schicht (recorded). Note must wrap.

### schedule-loading-empty-error-states - Loading, empty, offline and generic-error states inside the expanded schedule card  [PORT, size S, in_range]
- Android at 60f6886: Loading -> 'Einsätze werden geladen …' (text). Loaded empty -> 'Für die nächsten 31 Tage sind keine Einsätze geplant.' Failed(offline: status 0) -> 'Einsätze konnten ohne Verbindung nicht geladen werden.' + 'Erneut versuchen'. Failed(other, incl. 404/500/shape) -> 'Einsätze konnten nicht geladen werden.' + retry. 401 never shows here.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:119-128; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:1028; android/app/src/main/res/values/strings.xml:632-636
- iOS gap: None of the four sentences exists; only 'Try again' does.
- Port notes: Loader: catch APIFailure -> .failed(offline: status == 0); any other error -> .failed(offline: false). Do not route through workerMessage. Add the four de+en keys; reuse 'Try again'.

### schedule-manual-refresh - Refresh icon and Try-again re-fetch the schedule in place  [PORT, size S, in_range]
- Android at 60f6886: Card header icon button (content description 'Einsätze aktualisieren') and the failure retry both call loadSchedule(). The Shift tab's general refresh does NOT reload the schedule.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/WorkerHomeCards.kt:115,123,183; android/app/src/main/res/values/strings.xml:637; docs/product-launch-verification.md:52
- iOS gap: No control re-fetches a schedule.
- Port notes: Borderless Button with arrow.clockwise and accessibilityLabel 'Refresh assignments' (de 'Einsätze aktualisieren'; add by hand - accessibility labels are not extracted by localisation-check). Optionally also kick the load from .refreshable, concurrently.

## Files
Modify: NFCTimeSheets/NFCTimeSheets/API.swift, NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/ShiftScreen.swift, NFCTimeSheets/NFCTimeSheets/Localizable.xcstrings, NFCTimeSheets/checks/run.sh
Create: NFCTimeSheets/NFCTimeSheets/ScheduleStore.swift, NFCTimeSheets/NFCTimeSheets/ScheduleViews.swift, NFCTimeSheets/NFCTimeSheets/ViennaTime.swift, NFCTimeSheets/NFCTimeSheets/LoadGuard.swift, NFCTimeSheets/checks/schedule-check.swift
## Server contract
GET /me/schedule (worker session cookie + X-App-Key, no params; identity from session) -> 200 {assignments:[{id uuid string, location_name, starts_at, ends_at, note, ...extra}]}: this worker's uncancelled planned_shifts with ends_at > now and starts_at < now+31d, ordered by starts_at, max 200 (server/routes/schedule.js:23-31,171). 401 -> signed-out path; transport -> status 0; 404/500 -> generic error. Production may lack migration 025: tolerate 404/500.

## Strings
English keys (German from Android res, formal Sie): 'Next planned assignment' (worker_planned), 'View' (worker_show), 'Close' (worker_hide), 'My schedule' (schedule_title), 'Planned · Clock in separately' (worker_schedule_note), 'Loading assignments …', 'No assignments planned for the next 31 days.', 'Could not load assignments without a connection.', 'Could not load assignments.', 'Try again' (EXISTS), 'Refresh assignments' (schedule_refresh; accessibility label added by hand, not extracted by localisation-check), 'All upcoming assignments', 'Show less', '%@ · %@–%@' (schedule_same_day), '%@, %@ – %@, %@' (schedule_when). Resolved by the OS lookup today; the later decision-74 sweep routes them through AppLanguage.

## Checks
- NEW schedule-check.swift (cat Branding, TagLink, API, LoadGuard, ViennaTime): decode vectors (extra keys, .000Z and whole-second timestamps, note absent -> '', empty list, location_id NOT decoded); same-day vs cross-day in Europe/Vienna incl. 22:00-02:00, end exactly 00:00 = cross-day, DST boundary, device zone not Vienna; LoadGuard: stale token ignored, different worker resets, same worker keeps, cancelled request never publishes
- wire schedule-check into run.sh; do NOT edit tag-link-check.swift (parallel run has uncommitted edits)
- localisation-check.swift green

## Design rules from the plan
- OD2 (decision-78 proposal) must be recorded before this package merges (docs/product-launch-and-scheduling.md:36 says iOS scheduling is not added); planned as accepted.
- ScheduleStore: @MainActor @Observable held as @State in LogView (dies with LogView on sign-out; P3's .id(worker.id) resets it on a worker change; the store ALSO keeps its own worker-id + monotonic request token guard, LoadGuard.swift, reusable by P7). load() sets .loading first (previous list dropped, as Android), publishes only if the token is still latest and the worker unchanged.
- TRAP: API.swift send() converts every URLSession error, including a cancelled task, into APIFailure(0,'network') (API.swift:379-384), so a cancelled .task would paint the offline sentence. Use an unstructured Task plus the token, and check Task.isCancelled before writing .failed. 401 never renders here (the .sessionRejected path signs out). Offline = status 0 only.
- Triggers: LogView .onAppear (tab return), scenePhase .active (existing handler), the card's refresh icon and Try-again. NOT from refresh()/pull-to-refresh and never read by handleTap. Keep it concurrent with, never inside, the roster/sync pass.
- Fetch via apiGet (worker cookie jar), never OperatorAPI. WireScheduleAssignment {id, locationName, startsAt, endsAt, note=''} with explicit CodingKeys.
- Vienna time: ViennaTime (Foundation-only) with TimeZone Europe/Vienna, Date.FormatStyle with that timeZone, sameDay via a Vienna Calendar; reused by P7. Medium date, short time, OS locale (not AppLanguage). Two NON-positional keys differing only by dash spacing: '%@ · %@–%@' and '%@, %@ – %@, %@'; a wrong dash ships English silently, so copy exactly.
- Views are self-contained with NO hard-coded surface: ScheduleSummary (row + expanded flag in its own @State so ShiftScreen's minute TimelineView cannot collapse it), ScheduleCard, ScheduleAssignmentRow; the caller supplies the container. Collapsed + Loaded(>=1): first assignment's building and time line; collapsed while loading/failed/empty: nothing under the row (HEAD shape, WorkerHomeCards.kt:158-181; docs still describe three rows). Spell the toggle in words (Button row 'View'/'Close'), not a bare chevron.
- Idle placement: new Section between the unresolved banner and Section('Recent') (iOS's idle order puts Recent ABOVE the scan block, ContentView.swift:358). Running: inserted before helpCard in ShiftScreen's VStack (ShiftScreen.swift:86), label stays 'Next planned assignment' even if in progress. Expanded card: first assignment only, toggle 'All upcoming assignments' / 'Show less' lists all with dividers, note wraps in full; show-all resets on state change.
- Do not port schedule_explainer (dead). Keep Einsatz (plan) vs Schicht (recorded) wording. No new tab, no reminder.
- RISK: if production lacks the route every launch yields the generic error inside the expanded card only.

## Verification matrix (drive it; do not assert from source)
Idle (+) | worker with one same-day assignment, open Log | collapsed row 'Next planned assignment · View' with building and 'date · 08:00–12:00' in Vienna time | GET /me/schedule 200
Idle expand (+) | tap View | 'My schedule' card, 'Planned · Clock in separately', first assignment, 'All upcoming assignments' toggle only when >1; toggle lists all with notes | -
Cross-midnight (+) | assignment 22:00-02:00 | long form 'd, 22:00 – d+1, 02:00' | -
Empty (+) | no assignments | collapsed row shows nothing under it; expanded shows the 31-day sentence | 200 []
Offline (-) | server stopped | collapsed nothing; expanded 'without a connection' + Try again; Try again re-fetches | status 0
Route missing (-) | 404 | expanded generic error + Try again | 404
Session revoked (-) | 401 | app signs out; no schedule error rendered | 401
Running (+) | start shift, running screen | same row before the help card; expanding does not collapse after the minute tick
Resume (+) | switch tabs and back, background/foreground | each triggers one fetch; a slow stale response does not overwrite a newer one
Cancel (-) | leave the tab mid-request | no offline sentence painted
Identity (-) | A signs out, B signs in | B never sees A's assignment, store starts Loading
Refresh icon (+) | tap refresh icon | re-fetch, VoiceOver label 'Refresh assignments'
Decoupling (-) | schedule request fails | clock-in, sync and signals unaffected
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 decision-78 recorded (backlog decision create) BEFORE the code, and listed in the epic
- [ ] #2 Driven: Idle (+) | worker with one same-day assignment, open Log | collapsed row 'Next planned assignment · View' with building and 'date · 08:00–12:00' in Vienna time | GET /me/schedule 200
- [ ] #3 Driven: Idle expand (+) | tap View | 'My schedule' card, 'Planned · Clock in separately', first assignment, 'All upcoming assignments' toggle only when >1; toggle lists all with notes | -
- [ ] #4 Driven: Cross-midnight (+) | assignment 22:00-02:00 | long form 'd, 22:00 – d+1, 02:00' | -
- [ ] #5 Driven: Empty (+) | no assignments | collapsed row shows nothing under it; expanded shows the 31-day sentence | 200 []
- [ ] #6 Driven: Offline (-) | server stopped | collapsed nothing; expanded 'without a connection' + Try again; Try again re-fetches | status 0
- [ ] #7 Driven: Route missing (-) | 404 | expanded generic error + Try again | 404
- [ ] #8 Driven: Session revoked (-) | 401 | app signs out; no schedule error rendered | 401
- [ ] #9 Driven: Running (+) | start shift, running screen | same row before the help card; expanding does not collapse after the minute tick
- [ ] #10 Driven: Resume (+) | switch tabs and back, background/foreground | each triggers one fetch; a slow stale response does not overwrite a newer one
- [ ] #11 Driven: Cancel (-) | leave the tab mid-request | no offline sentence painted
- [ ] #12 Driven: Identity (-) | A signs out, B signs in | B never sees A's assignment, store starts Loading
- [ ] #13 Driven: Refresh icon (+) | tap refresh icon | re-fetch, VoiceOver label 'Refresh assignments'
- [ ] #14 Driven: Decoupling (-) | schedule request fails | clock-in, sync and signals unaffected
- [ ] #15 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #16 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [ ] #17 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [ ] #18 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
