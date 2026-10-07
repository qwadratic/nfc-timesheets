---
id: TASK-365.3
title: 'iOS P2: ''Start without a tag'' picks a zone and asks the server first'
status: To Do
assignee: []
created_date: '2026-10-07 12:21'
labels:
  - ios
  - parity
  - worker
dependencies:
  - TASK-365.2
parent_task_id: TASK-365
priority: high
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Manual start lists cached zones ('Building · Zone') and posts the ZONE uuid with manual:true. The server's refusal is shown inside the sheet and writes no row; only a network failure falls back to iOS's existing local-first queue. Copy says zone.
## Decision to record FIRST (decision-77)
Record decision-77: manual start picks a ZONE and asks the server first (amends decision-56 §2 and §4; completes decision-69 for the worker phones)?
Context: decision-56 §2/§4 say the worker 'picks a building'. Since decision-69 a building UUID is no clock-in target, so iOS's manual start (building picker ContentView.swift:425-480, post via handleTap/Sync.swift:98-131) is refused 422 unknown_location (server/lib/validate.js:560-612) and the local row sits blocked behind a normal-looking running screen; the DEBUG mock hides it (ShiftMocks.opened echoes any id). Android fixed it in fef7717 (TASK-347): zone picker 'Building · Zone', online POST, refusal inline, nothing written. Proposed rule: (1) picker = cached roster zones whose building is cached, flat, sorted, unverified included, nothing preselected; (2) post the ZONE uuid with manual:true; (3)
Recommendation (planned as accepted): Accept as written. It is the only option that keeps iOS's offline manual start AND shows the server's refusal where the worker is looking. Planned as accepted.

## Items (Android evidence at 60f6886)
### manual-start-picks-zone - 'Start without a tag' must pick a ZONE and post its UUID; iOS posts a building UUID the server refuses  [IOS_BREAKAGE, size M, in_range]
- Android at 60f6886: ManualStartDialog lists every cached roster zone whose building is cached (manualPlaces(): sorted by building then zone), labelled '<Building> · <Zone>', flat, nothing preselected, unverified zones included. Start disabled until a pick. manualOpen refuses locally (409 shift_already_open) if a shift is open, else POST /shifts/open {client_uuid, location_uuid: ZONE uuid, start_time, manual: true} online. 201: server row (location_id = building) adopted as synced, signals armed. Any failure (422 zone_unverified/unknown_location/tag_unbound, 409, offline) shown in the dialog via the tap path's string keys; nothing written. Before fef7717 Android 
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:809-856; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1352-1450; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/Wire.kt:472-495
- iOS gap: The Picker iterates pickableSites = Site rows (building ids) and startManual() passes that id to handleTap(id, manual: true) (read). activePlace resolves only zones/aliases (validate.js:560-612, read; decision-69 commit df7c6d3 is an ancestor of 8aafbf1), so the POST gets 422 unknown_location, terminal -> syncBlocked. Because iOS writes locally first the worker sees a normal running shift for one the server never created; the stop is never sent; the hours never arrive. Every iOS manual start fails against the curre
- Port notes: Needs worker-roster-zone-cache. Foundation-only Zones.manualPlaces(zones:buildingNames:) ported from manualPlaces; picker rows 'Building · Zone' (key '%@ · %@' exists), first row 'Choose a zone' tagged nil, post the zone id; OpenShiftRequest unchanged. BuildingPicker.swift (operator) untouched. Never map a building to a 'first' zone. Mocks hide this bug today (canned building, echoing response): replace with a canned building+zone, return the building id as location_id, add refusal flows (422 x3, 409). zones-check: ordering, missing-building filter, empty case, and a text assertion that the picker is never fed Site ids.

### manual-start-zone-copy-and-empty-state - Manual-start copy says zone; empty state tells the worker to refresh then contact the office  [PARTIAL, size S, in_range]
- Android at 60f6886: manual_start_intro changed to '... Wählen Sie die Zone im Objekt, in der Sie jetzt arbeiten. Die Schicht wird für das Büro als manueller Start markiert.'; empty list shows manual_start_no_zones 'Es sind keine Zonen verfügbar. Bitte zuerst aktualisieren. Fehlt Ihre Zone weiterhin, melden Sie sich bei der Verwaltung.' (replaces deleted manual_start_no_buildings); label manual_place_label '%1$s · %2$s'.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:1387-1393; android/app/src/main/res/values/strings.xml:111-113; android/app/src/main/res/values-en/strings.xml:76-78
- iOS gap: iOS copy speaks of buildings ('Pick the building instead...', 'Building', 'Choose a building', 'No buildings on this phone yet...') and has no contact-the-office sentence.
- Port notes: New de+en entries for intro/footer, prompt 'Choose a zone', empty state (German from strings.xml:111-112). Do NOT repurpose 'Building'/'Choose a building' (operator BuildingPicker uses them). iOS manual-flow German is informal du; Android is formal Sie - align.

## Files
Modify: NFCTimeSheets/NFCTimeSheets/ContentView.swift, NFCTimeSheets/NFCTimeSheets/Sync.swift, NFCTimeSheets/NFCTimeSheets/Zones.swift, NFCTimeSheets/NFCTimeSheets/Localizable.xcstrings, NFCTimeSheets/checks/zones-check.swift, NFCTimeSheets/checks/shift-signal-check.swift, NFCTimeSheets/checks/run.sh
Create: NFCTimeSheets/NFCTimeSheets/ManualStart.swift, NFCTimeSheets/checks/manual-start-check.swift
## Server contract
POST /shifts/open {client_uuid, location_uuid: ZONE uuid, start_time, manual:true} -> 201 new / 200 duplicate / 409 shift_already_open / 422 zone_unverified | unknown_location | tag_unbound (server/routes/app.js:182-227, validate.js:560-612). A building uuid is ALWAYS 422 unknown_location since decision-69 (server/check-api.js:5244-5264).

## Strings
New keys (English sentence is the key, German in the de entry): 'Choose a zone', 'Zone', manual intro (Android manual_start_intro), empty state (manual_start_no_zones), '%@ · %@' (manual_place_label), idle footer 'Tag missing or unreachable? Pick the zone instead. The office sees this as a manual entry.' German from android/app/src/main/res/values/strings.xml, English from values-en. Update the existing manual strings that say building.

## Checks
- NEW manual-start-check.swift (cat Branding, TagLink, API, Zones, ManualStart): classify(APIFailure) - 422 zone_unverified/unknown_location/tag_unbound, 409 shift_already_open, 401 => refuse (no row); status 0, 408, 429, >=500 => queue (local-first); mirrors the failure vocabulary of android ManualStartDialog
- EXTEND zones-check.swift: manualPlaces = cached zones whose building is cached, sorted building name then zone name, unverified included, label '<Building> · <Zone>', empty when no zones or no cached building
- EXTEND shift-signal-check.swift: handleTap still saves before arm and contains no 'try await' before the save (the online attempt lives in startManual, not in handleTap)
- localisation-check.swift green; wire manual-start-check into run.sh

## Design rules from the plan
- OD1 (decision-77 proposal) governs this package; planned as accepted.
- Picker = P1's cache: zones whose building is in Site rows, flat, nothing preselected, 'Choose a zone' row first, Start disabled until a pick (Android manualPlaces, TimeSheetViewModel.kt:809-815). Sort with localizedStandardCompare (Android uses code-point order; cosmetic deviation).
- Flow (sibling item manual-start-online-with-inline-refusals, absent from the list, ported here): startManual() generates ONE client_uuid and start time, calls ShiftFlowAPI.open(manual:true) with the zone id BEFORE any local write; success -> handleTap(zoneId, manual:true, clientUuid:, acked: envelope) writes the Shift already acknowledged (openSyncedAt, serverId, manualStart) through an internal variant of Sync.swift apply(); refusal -> inline error in the sheet via APIFailure.workerMessage, no row, sheet stays, Start usable again; transport/408/429/5xx -> existing local-first handleTap(manual:true) REUSING the same client_uuid so a retry cannot double-open. handleTap stays the one write path; its text-read ordering must not change.
- If a shift is already open locally, answer 409 shift_already_open inline without a request (Android manualOpen). Known wording gap shared with Android: err 'Another shift is still running - finishing it first.' is untrue for a refused manual start; reuse it for parity.
- Copy: take German verbatim from Android (formal Sie) for new strings; do NOT repurpose 'Building'/'Choose a building' (operator BuildingPicker.swift uses them). Delete 'No buildings on this phone yet...' only if grep shows it unused.
- DEBUG mock stays: ShiftMockFlows.swift is NOT edited. The existing `#if DEBUG` merge of ShiftMocks.locations into pickableSites (ContentView.swift:461-469) is re-pointed to append one mock zone built from locations[0] so the armed mock still walks; never offer a building as pickable.
- Confirmation dialog stays (decision-56 §4) and now names the zone label ('Start a shift at %@?').
- RISK: rows already blocked in the field stay blocked (no auto-retry). Telemetry.log a 'manual start refused' line with ts.api.code.

## Verification matrix (drive it; do not assert from source)
Idle/manual sheet (-) | open with no cached zones (fresh, offline) | empty sentence 'No zones are available. Please refresh first...' | no request
Idle/manual sheet (+) | open with cached zones | rows 'B · Z' sorted, none selected, Start disabled until picked, confirm dialog names the label
Start online verified zone (+) | pick, Start, confirm | sheet closes, running screen, row acked at once, 'Manual' pill later | POST /shifts/open location_uuid=Z manual:true -> 201, shifts.manual_start=true, location_id=B
Unverified zone (-) | pick zone with verified_at null | inline 'This tag hasn't been activated yet. No shift was started...', sheet open | no local row, no server row
Other open shift on server (-) | second device holds an open shift | inline 409 sentence | no row
Deactivated zone (-) | zone deactivated after cache | inline 'This location was removed...' | no row
Server down (-) | stop server, Start | sheet closes, running screen, local row queued; start server + pull-to-refresh | exactly ONE server row (201 or duplicate 200), same client_uuid
Wire (-) | inspect requests | no POST /shifts/open ever carries a building uuid
Mock armed (+) | arm 'accepts a manual start', pick the mock zone, Start | works with no server (ShiftMocks echo)
Stop without tag (regression) | Finish shift without a tag | still closes with manual:true
## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 decision-77 recorded (backlog decision create) BEFORE the code, and listed in the epic
- [ ] #2 Driven: Idle/manual sheet (-) | open with no cached zones (fresh, offline) | empty sentence 'No zones are available. Please refresh first...' | no request
- [ ] #3 Driven: Idle/manual sheet (+) | open with cached zones | rows 'B · Z' sorted, none selected, Start disabled until picked, confirm dialog names the label
- [ ] #4 Driven: Start online verified zone (+) | pick, Start, confirm | sheet closes, running screen, row acked at once, 'Manual' pill later | POST /shifts/open location_uuid=Z manual:true -> 201, shifts.manual_start=true, location_id=B
- [ ] #5 Driven: Unverified zone (-) | pick zone with verified_at null | inline 'This tag hasn't been activated yet. No shift was started...', sheet open | no local row, no server row
- [ ] #6 Driven: Other open shift on server (-) | second device holds an open shift | inline 409 sentence | no row
- [ ] #7 Driven: Deactivated zone (-) | zone deactivated after cache | inline 'This location was removed...' | no row
- [ ] #8 Driven: Server down (-) | stop server, Start | sheet closes, running screen, local row queued; start server + pull-to-refresh | exactly ONE server row (201 or duplicate 200), same client_uuid
- [ ] #9 Driven: Wire (-) | inspect requests | no POST /shifts/open ever carries a building uuid
- [ ] #10 Driven: Mock armed (+) | arm 'accepts a manual start', pick the mock zone, Start | works with no server (ShiftMocks echo)
- [ ] #11 Driven: Stop without tag (regression) | Finish shift without a tag | still closes with manual:true
- [ ] #12 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #13 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n); a new file is grepped for String(localized:) / LocalizedStringKey
- [ ] #14 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary (AGENTS.md review gate)
- [ ] #15 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
