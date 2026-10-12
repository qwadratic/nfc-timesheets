---
id: TASK-365.2
title: >-
  iOS P1: a new zone is read - roster zones cached, building names,
  same-building rule
status: Done
assignee: []
created_date: '2026-10-07 12:20'
updated_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - worker
  - zones
dependencies:
  - TASK-365.1
parent_task_id: TASK-365
priority: high
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A zone created after the last roster fetch is known without pull-to-refresh, and a tap-started shift shows its BUILDING everywhere (running screen, Recent, History, stop dialog, switch notice, reminders, material context). Two zone taps in one building toggle, never switch. Material requests carry the building id, not the zone id.

## Why (found while fixing the zone report)
The worker phone had no idea which building a zone belongs to. Every tap-started shift read "Unknown location"; tapping out at a building's SECOND door auto-closed the shift as a walk-away and opened a new one flagged for correction; a material request carried a zone id the server answers 422 for ever. Android has had the zone cache since the zone model landed.

## Items
### worker-roster-zone-cache - Prerequisite: worker app decodes and caches roster zones (id, building, name, serial)  [PORT, size M, pre_existing]
- Android at 60f6886: GET /roster returns locations plus zones [{id, location_id, name, tag_serial|null}] (every active zone of an active building; serial only when verified). Wire.roster reads zones leniently; refreshRoster replaces both tables in one transaction; ShiftStore.zones() serves them offline; LogState carries them since 3f4982d. Zones.buildingIdOf(placeId, zones) returns the building id or the id itself on a miss (never a sentinel); zonePlaceIdForSerial. Cache predates the range (2026-08-19).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/Wire.kt:91-116,338-341; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/data/ShiftStore.kt:255-318; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/data/ShiftSync.kt:77-88
- iOS gap: WireRoster decodes locations only (API.swift:258-260, read); only Site rows are cached; no worker zone type. Zones.swift ported normaliseSerial only. Since decision-69 every card carries a zone/alias UUID iOS cannot map. Foundation for building names, same-building rule, manual zone start, material context, serial lookup.
- Port notes: API.swift: WireZone {id, location_id, name, tag_serial?} and OPTIONAL zones on WireRoster (decodeIfPresent ?? []). Cache as JSON/UserDefaults like OperatorZoneCache.swift, written from refreshRoster. Add to invalidateCachesIfUpdated + AppUpdate.swift header (decision-62) or exempt deliberately. Zones.swift: port buildingIdOf and zonePlaceIdForSerial clause for clause, Foundation-only. New checks/zones-check.swift in run.sh (zone->building, unknown->itself, empty cache->itself) + roster decode with/without zones in tag-link-check. Canned zones next to ShiftMocks.locations.

### zone-shift-shows-building-name - A shift stored with a zone id shows its building's name everywhere  [PORT, size S, in_range]
- Android at 60f6886: siteName(id) = locationNames[Zones.buildingIdOf(id, zones)]; used by running screen, recent/history rows, receipt, stop dialog, material context, switch notice, ongoing notification, BootReceiver and the manual picker label. Before 3f4982d zone shifts read 'Unbekanntes Objekt' (found in the first driven pass).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:916-918; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/notify/Receivers.kt:61-66; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/Zones.kt:31-32
- iOS gap: The three private siteName helpers look the raw locationId up among Site rows (buildings). A tapped shift keeps the zone UUID (apply() never rewrites locationId), so header, stop dialog, Recent/History, reminders, switch notice and Live Activity show 'Unknown location'. Only server-adopted rows resolve. Derived from source, not driven.
- Port notes: After worker-roster-zone-cache: one shared resolver (Zones.buildingIdOf then Site lookup) replacing the copies in LogView, HistoryView, MaterialsView and asRunning; resolve before signals.arm (Live Activity attributes are fixed at start). Interim without the cache: store envelope.shift.locationName in Sync.apply (offline taps still unknown until sync). No strings. Simulator: --ts-demo-tap <zone uuid> against the loopback fixture.

### material-request-building-not-zone - Material request context must be the BUILDING of the open shift; iOS sends the zone UUID and gets 422  [IOS_BREAKAGE, size S, pre_existing]
- Android at 60f6886: submitMaterial maps the open shift's place id through Zones.buildingIdOf before queueing; POST /material-requests validates location_uuid with activeLocation (buildings only, decision-6). Since 9239527.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:967-983; server/routes/app.js:546-553; server/lib/validate.js:528-532
- iOS gap: contextLocationId = openShift?.locationId passed unchanged (MaterialsView.swift:36,126, read). For a tap-started shift that is a zone UUID; activeLocation answers 422 unknown_location (read); MaterialQueue marks the request blocked. Requests with no open shift or during a server-adopted shift go through. Found by reading, not driving.
- Port notes: After the zone cache: contextLocationId = Zones.buildingIdOf(openShift.locationId, zones), nil if it is not a known Site; same mapping for the 'For %@' label. Vector in checks/materials-check.swift. Confirm against a real server before scheduling. Consider how to surface outbox rows already blocked (do not auto-resend silently).

### foreground-roster-refresh - Returning to the foreground refetches the roster and re-arms signals  [PARTIAL, size S, in_range]
- Android at 60f6886: onForeground (every resume of the signed-in scaffold) arms signals, fetches GET /roster off main, merges ONLY locationNames and zones into the latest state (_log.update, never a pre-tap snapshot) and arms again. Failure silent. Purpose: a zone just activated on the same phone is known without a tap.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetViewModel.kt:675-688; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/TimeSheetApp.kt:824-829
- iOS gap: On scenePhase .active iOS only re-arms and re-reads notification authorization (ContentView.swift:338-342, read); the roster is fetched on LogView mount and pull-to-refresh only.
- Port notes: In the scenePhase handler add Task { await refreshRoster(context: context); signals.arm(for: currentRunning()) } - roster only, not the full refresh(); fire-and-forget. Popping back from OperatorHomeScreen is not a scene change: also refresh on LogView appear. No strings.

## Server contract
GET /roster -> {locations, zones:[{id, location_id, name, tag_serial|null}]} (server/routes/app.js:99-165; every active zone of an active building, serial only when verified; key may be absent on an old server = empty). POST /material-requests location_uuid is validated by activeLocation = BUILDING ids only (server/lib/validate.js:528-532); a request with no building is valid (app.js:546-553).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GET /roster zones decoded leniently (missing key, null, wrong type, one malformed zone) and cached; replaced only on a SUCCESSFUL roster
- [x] #2 Every list shows the zone's BUILDING name (Log, History, resolver, switch notice); fallback stays "Unknown location"
- [x] #3 handleTap compares BUILDINGS: tapping out at a second zone of the same building closes the shift (no switch card, no auto-close)
- [x] #4 Roster refreshed after a tap (own un-awaited Task, after save and arm) and on foreground; never gates a tap
- [x] #5 A material request carries the building id, never a zone id
- [x] #6 zones-check + extended shift-signal-check green, three red cases reproduced; Debug and Release build
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
tag_aliases ids are not published by GET /roster (server/routes/app.js zones only), so a card adopted by an existing zone still shows Unknown location on BOTH platforms; fixing it needs a server change (separate task). Zone/Site caches are not cleared on sign-out or worker change; decide in P3.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
iOS now caches GET /roster zones (RosterZones, one JSON snapshot replaced on a successful roster), resolves the BUILDING name for every list (Zones.buildingName), compares buildings in handleTap so tapping out at a second door closes instead of auto-closing, refreshes the roster after a tap and on foreground (own un-awaited Task, after save and arm), and attaches the building (never a zone id) to a material request. Commit 57e2339. Verified: zones-check (roster decode vectors, buildingIdOf/buildingName/materialContext/serial lookup) and the extended shift-signal-check with three red cases reproduced (same-building rule reverted, post-tap refresh removed, material request sending the zone id); Debug and Release build. NOT verified: a driven simulator walk against a real roster (needs the loopback demo server with a database; see the verification task).
<!-- SECTION:FINAL_SUMMARY:END -->
