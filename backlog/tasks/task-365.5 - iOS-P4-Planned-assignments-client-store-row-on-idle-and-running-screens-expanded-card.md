---
id: TASK-365.5
title: >-
  iOS P4: Planned assignments: client, store, row on idle and running screens,
  expanded card
status: In Progress
assignee: []
created_date: '2026-10-07 12:21'
updated_date: '2026-10-07 13:18'
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
- [x] #1 decision-78 recorded (backlog decision create) BEFORE the code, and listed in the epic
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
- [x] #15 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [x] #16 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [x] #17 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [x] #18 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision number: the plan called this decision-78/79/80, but 77 and 78 are taken by branch admin-declutter and 79 is manual start. Record it with backlog decision create (next free number) BEFORE the code.

2026-10-07 implementation complete on branch ios-worker-parity (code commit: see the git log entry "ios: planned assignments ... (P4, decision-80)"). Status stays In Progress: criteria #2-#14 are DRIVEN walks that need a signed-in WORKER session against a server, and no rig provides one (decision-50 retired the Apple-token path; TASK-365.22 is that rig, not yet built). Nothing was driven and nothing is claimed as driven. Criteria #1, #15, #16, #17, #18 are met and ticked.

DECISION: decision-80 (backlog decision create assigned the number; the plan's "78" belongs to branch admin-declutter) - the iOS worker app shows the signed-in worker's planned assignments, READ-ONLY and DISPLAY-ONLY; amends decision-73 and docs/product-launch-and-scheduling.md (its sentence "iOS scheduling is not added in this iteration" now points at decision-80). Recorded BEFORE any code; one-line entry in the AGENTS.md checklist; note on the epic TASK-365.

WHAT CHANGED
- API.swift: WireScheduleAssignment {id, locationName, startsAt, endsAt, note} (explicit CodingKeys; note decodeIfPresent ?? ''; location_id and every other server key NOT decoded), WireScheduleEnvelope (lossy per row), ScheduleAPI.mine() = apiGet("/me/schedule"), no query, worker cookie jar.
- LoadGuard.swift (new, Foundation-only, needs WorkerScope.swift): Ticket(generation, workerId); begin(for:), adopt(_:) (different worker -> true, same -> false), accepts(_:sessionWorkerId:cancelled:). Reusable by P7.
- ViennaTime.swift (new, Foundation-only): ViennaTime.zone/calendar/date/time/sameDay (DateFormatter MEDIUM/SHORT, zone pinned explicitly, cached per locale) and ScheduleTimeLine.text(from:to:locale:) = the two non-positional keys "%@ · %@–%@" (same Vienna day) / "%@, %@ – %@, %@" (across midnight).
- ScheduleStore.swift (new): ScheduleState {loading, loaded([..]), failed(offline:)} + ScheduleState.after(failure:); @MainActor @Observable ScheduleStore.load(for:session:) - no-op unless the worker holds the session, supersedes+cancels the request in flight, sets .loading FIRST, own UNSTRUCTURED Task, publishes only if latest + same worker still holds the session + not cancelled. In memory only.
- ScheduleViews.swift (new): ScheduleSummary (collapsed "Next planned assignment" + View/Close, expanded flag in its own @State), ScheduleCard ("My schedule", refresh icon, caption, loading/empty/offline/error + Try again, first assignment, "All upcoming assignments"/"Show less" with dividers, show-all resets on state change), ScheduleAssignmentRow. No surface of its own; every Button .borderless.
- ContentView.swift: @State schedule = ScheduleStore() in LogView; loadSchedule() = the one trigger, called from .onAppear on the NavigationStack (LogView.body now returns `content.onAppear`, so the idle/running Group swap does not refetch) and LAST in the existing scenePhase .active handler, after arm + roster; a new Section { ScheduleSummary } between the unresolved banner and Recent; state + reload passed to ShiftScreen. Not in refresh(), not in handleTap, not in .refreshable.
- ShiftScreen.swift: schedule + onReloadSchedule; scheduleCard (card(icon: "calendar")) after notificationsOffCard, before helpCard.
- Localizable.xcstrings: 14 new keys (13 sentences + the two time-line templates; 'Try again' already existed), German read OUT of android/.../values/strings.xml by script (node scratchpad/p4/catalog-patch-p4.js), English key asserted equal to Android's English.
- checks/schedule-check.swift (new, wired into run.sh); AGENTS.md; docs/product-launch-and-scheduling.md; decision-80.

PLAN'S OPEN QUESTION (production without migration 025 / the route): confirmed against Android at 60f6886 (WorkerHomeCards.kt WorkerScheduleSummary): the collapsed row shows something under the label ONLY for Loaded with >= 1 row; loading / failed / empty show nothing there; only the expanded card says "Einsätze konnten nicht geladen werden." (404/500/shape = generic, status 0 = offline). iOS does exactly that, so a server without the route costs the worker nothing on the idle or running screen and one generic sentence inside the card.

DECISIONS TAKEN WHERE THE TASK LEFT A QUESTION
1. LENIENT DECODE (per the run brief): one unreadable row drops that row, neighbours survive (Android's strict map would fail the whole list). Exception: rows were sent and NONE is readable -> throws -> generic error, because "no assignments planned" would be a false statement to a worker with a full week.
2. A 401 renders NOTHING: ScheduleState.after(failure:) returns nil for it and the state stays .loading (API.swift's send() already posted .sessionRejected; the app is signing out). Android could flash Failed for the instant before sign-out; iOS does not.
3. DateFormatter (dateStyle .medium / timeStyle .short, zone pinned) instead of Date.FormatStyle: measured on this Mac, FormatStyle .shortened gives "8:00" where the locale and Android give "08:00". Same-day test is a Vienna Calendar, not a comparison of formatted strings (equivalent; the end-at-00:00 vector pins it). de_AT date reads "14.01.2026" like Android.
4. NO new DEBUG canned schedule flows (the task's port notes asked for a ScheduleFlowAPI seam): the owner's scope rule and the run brief forbid new mocks, and without a worker session a mock screen could not be reached anyway. The store takes an injectable fetch; that is how the check drives the REAL store.
5. .refreshable / pull-to-refresh does NOT reload the schedule (Android: the Shift tab's general refresh does not); the task's "optionally also kick the load from .refreshable" is declined.
6. Placement follows the task text (above Recent), not Android's order, because iOS puts Recent above the scan block.
7. `schedule_explainer` (dead on Android) is not ported. Einsatz (plan) vs Schicht (recorded) kept.
8. Locale is the OS's (Locale.current), not AppLanguage; E1 (decision-74) must route ScheduleTimeLine.text and the date/time formatters through AppLanguage.
9. docs/product-launch-and-scheduling.md line 36 was edited (one sentence) so the document does not contradict decision-80.

VERIFIED
- checks/run.sh: every check green. New: "schedule-check: OK". "localisation-check: OK (298 keys, all German)" (was 284 + the 14 new keys). "checks: OK".
- schedule-check covers: wire decode vectors (full server row with extra keys; .000Z, whole-second and mixed timestamps; note absent / null; empty list; server order kept; one malformed row dropped; all-malformed throws; missing / null / non-array 'assignments' throws; exactly five fields, no location_id); Vienna time: 11 fixed-instant cases (winter and summer same-day, 22:00-02:00 in winter and summer, end at exactly 00:00, start at 00:00, same day in UTC but two days in Vienna, both DST changes incl. the 25-hour day and the repeated 02:30) x en_GB and de_AT x five device zones (Los Angeles, Auckland, UTC, Kolkata, Vienna - this Mac is Vienna, so the override matters); LoadGuard (stale, other worker, nobody, cancelled, adopt same / different); the REAL ScheduleStore with an injected fetch (round trip, one fetch per load, reload drops the list, stale in both arrival orders, offline = status 0 only, 404/500/503/decode/other = generic, 401 = nothing, cancelled never paints offline or publishes, superseded is cancelled, sign-out mid-flight, worker change mid-flight on one store, a refused load is a no-op); wiring read as text (the schedule appears in exactly eight lines of ContentView.swift, never in refresh/handleTap/startManual/manualStop/scan/currentRunning/armIfStillCurrent, foreground load after the arm, .onAppear on the stack, idle and running placement, 16 other files never mention it, nothing persisted, no surface in the views, only .primary/.secondary/.tint, every Button .borderless, Text(verbatim:) only for data); strings (every literal is a both-language key, the two templates extracted from ViennaTime.swift as text equal catalogue keys to the character, German = Android's verbatim, English key = Android's English).
- RED cases reproduced (mutate the real file, auto-restore, harness scratchpad/red-p4.sh + red-p4b.sh; all files restored byte-for-byte). First FAIL line of each: RED1 formatter without a zone -> "[America/Los_Angeles] en_GB: winter, same day 08:00-12:00 CET: got '13 Jan 2026 · 23:00–03:00'"; INFO1 only the formatter's own timeZone line dropped (calendar still Vienna) -> same FAIL (so the explicit line is load-bearing); RED2 sameDay in Calendar.current -> "[America/Los_Angeles] sameDay: winter, same day 08:00-12:00 CET"; RED3 compact dash as hyphen -> "got '14 Jan 2026 · 08:00-12:00'"; RED4 long dash loses a space -> "got '14 Jan 2026, 22:00 –15 Jan 2026, 02:00'"; RED5 compact/long decided by duration -> "winter night 22:00-02:00 crosses midnight: got '14 Jan 2026 · 22:00–02:00'"; RED6 stale ticket accepted -> "a STALE ticket (a newer request began) is ignored"; RED7 adopt(same) resets -> "the SAME worker keeps: no reset, nothing superseded"; RED8 cancelled may publish -> "a CANCELLED request never publishes, whatever else is true"; RED9 worker not compared -> "an answer for A is dropped once B holds the session"; RED10 load() keeps the old list -> "a reload drops the previous list at once"; RED11 401 paints generic -> "a 401 renders NOTHING ... got failed(offline: false)"; RED12 everything offline -> "404 (production without the route) is the generic error: got failed(offline: true)"; RED13 cancellation not passed on -> "a CANCELLED request does not paint the offline sentence: failed(offline: true)"; RED14 session not re-asked after the await -> "an answer that lands after sign-out is dropped"; RED15 superseded not cancelled -> "starting a new load cancels the one in flight"; RED16 load for a non-session worker -> "a load for a worker who does not hold the session asks nothing"; RED17 store touches UserDefaults -> "ScheduleStore.swift persists nothing"; RED18 strict decode -> "unreadable rows are dropped one by one and their neighbours survive ([])"; RED19 note required -> "a fractional start and a whole-second end in one row both decode" (+4); RED20 location_id decoded -> "WireScheduleAssignment has exactly id, locationName, startsAt, endsAt, note - no location_id"; RED21 all-malformed read as empty -> "rows sent but none readable THROWS"; RED22 worker id in the query -> "ScheduleAPI.mine is apiGet(\"/me/schedule\") with no query and no worker id"; RED23 load inside refresh() -> "refresh() never reads, awaits or waits for the schedule"; RED24 handleTap touches it -> "handleTap never reads, awaits or waits for the schedule"; RED25 no .onAppear -> "the schedule loads on the Log tab's appearance, from the NavigationStack"; RED26 section after Recent -> "idle: the 'Next planned assignment' section sits between the unresolved banner and Recent"; RED27 foreground loads before the arm -> "the schedule load comes AFTER the arm and the roster pass"; RED28 TabView loses .id(worker.id) -> "the TabView still carries .id(worker.id) (P3)"; RED29 card after help -> and RED30 no card -> "running: the schedule card sits after the notifications-off card and before the help card"; RED31 Sync.swift mentions the store -> "Sync.swift does not know the schedule exists"; RED32 .background in the views -> "ScheduleViews.swift has no hard-coded surface (found '.background(')"; RED33 a Button loses .borderless -> "every Button in a List row is .borderless (4 buttons, 3 borderless)"; RED34 Text(verbatim:) for a sentence -> "ScheduleViews.swift shows 'Loading assignments …' through the catalogue" (this one was GREEN against the first draft of the check; the check was strengthened and re-run red); RED35 .orange -> "only semantic colours (.primary / .secondary / .tint) are used"; RED36 a view reaches for the store -> "ScheduleViews.swift is display only: it cannot reach 'ScheduleStore'"; RED37 wrong German -> "the German for 'My schedule' is Android's schedule_title, verbatim: 'Mein Zeitplan' vs 'Meine Einsätze'"; RED38 key with the wrong dash spacing -> "the catalogue has the EXACT key '%@, %@ – %@, %@'"; RED39 'View' removed -> schedule-check "'View' has a German value" AND localisation-check "ScheduleViews.swift shows the literal 'View' and the catalogue has no entry for it"; RED40 German template drops a placeholder -> schedule-check "the German same-day template fills in" AND localisation-check "'%@ · %@–%@' ... the placeholders do not match". Baseline GREEN.
- node ops/check-branding.mjs: 14 lines, all "ok", "check-branding: OK"; no TODO line and no non-ok line printed on this branch.
- Debug and Release builds (generic/platform=iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED both; no warning in any touched file (the 9 warnings are the pre-existing MaterialStore.swift:54 and WriteGuard.swift:122 ones, identical to the P3 baseline). The four new .o files are in both targets (file-system-synchronized group, no pbxproj edit); the Release binary contains neither debug marker. The compiled de.lproj/Localizable.strings holds the new keys, including both dash keys, with Android's German. No edit to project.pbxproj or NFCTimeSheets.entitlements.
- Extra evidence, throwaway and NOT committed, NOT a UI drive: ScheduleViews.swift compiled into a macOS script and the pure rows rendered with ImageRenderer from injected data with the device zone set to Los Angeles: building + date/time lines wrap and read correctly, a cross-midnight row reads "09.10.2026, 22:00 – 10.10.2026, 02:00", a long note wraps in full. ImageRenderer cannot draw Buttons, so the controls were not seen.

NOT VERIFIED (criteria #2-#14 stay open): that .onAppear fires on every return to the Log tab inside the TabView; that the scenePhase and tab triggers each cost exactly one request; that expanding survives ShiftScreen's minute TimelineView tick; VoiceOver reading "Refresh assignments" / "Einsätze aktualisieren"; any of the rendered states against a real or loopback server (loaded, cross-midnight, empty, offline, 404, 401 sign-out, cancel by leaving the tab, A-to-B sign-in); that a failing schedule leaves a real clock-in untouched (pinned as source text and by the store's own tests, not driven). The Buttons' layout inside a List row and inside the running card was not seen.

RESKIN COLLISIONS (B1-B5 must touch these): (1) ContentView.swift idleList: `Section { ScheduleSummary }` sits above Section("Recent"); B2's new idle order (day heading, start card, action first, receipts as cards) has to move it (Android: after the start card, delivery rows and NFC banner, before Recent) and swap the List-row container for a card. (2) ShiftScreen.swift scheduleCard uses the current card() helper (secondary-background rounded rectangle + SF icon) and system text colours; B3's fixed dark-blue field needs on-blue ink - ScheduleSummary has no `ink` parameter (Android passes onContainer), so B3 either adds one or sets the foreground style on the container. (3) .borderless buttons take the system tint; B1's tokens decide the accent. (4) Fonts are system text styles (.headline / .subheadline / .footnote); B1's type tokens replace them in ScheduleViews.swift only. (5) The SF symbol "calendar" and "arrow.clockwise" are placeholders for the reskin's icons. (6) LogView.body is now `content.onAppear { loadSchedule() }` with the NavigationStack in `content`: keep the onAppear on the stack, not on the idle/running Group, or starting a shift refetches. (7) schedule-check pins the CURRENT structure as text (exact eight ContentView lines, the idle section order, scheduleCard before helpCard, the foreground handler order): a reskin that moves things must update those assertions in the same commit; that is their job. (8) None of the new strings change; only the placement and styling do.

Code commit: 12b0f72 (ios: planned assignments ... (P4, decision-80)). This notes commit follows it.
<!-- SECTION:NOTES:END -->
