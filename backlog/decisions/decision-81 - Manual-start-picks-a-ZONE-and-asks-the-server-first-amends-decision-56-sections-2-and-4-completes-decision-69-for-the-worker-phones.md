---
id: decision-81
title: >-
  Manual start picks a ZONE and asks the server first - amends decision-56
  sections 2 and 4, completes decision-69 for the worker phones
date: '2026-10-12 09:22'
status: accepted
---
## Context

(Recorded as decision-79 on branch ios-worker-parity on 2026-10-07, before 79 was taken on main by the agent-integration decision; renumbered 81 before merging. The text below is unchanged.)

decision-56 sections 2 and 4 say the worker "picks a building" for a manual start. Since decision-69 a building UUID is no clock-in target: `activePlace` resolves only zones and tag aliases, so POST /shifts/open with a building id is ALWAYS 422 `unknown_location`.

Android fixed this in PR 7 (fef7717, TASK-347): the manual-start dialog lists cached roster ZONES as "Building · Zone", posts the zone id with `manual: true` ONLINE, shows a refusal inside the dialog and writes nothing. iOS never followed. iOS posts the picked BUILDING id through the same local-first `handleTap` a tag uses, so the worker sees a normal running shift, the row is refused 422 in the background and sits `syncBlocked`, the stop is never sent and the hours never arrive. The DEBUG mock hid it: `ShiftMocks.opened` echoes any id with a 201.

The two halves each have a precedent: Android's online request with inline refusals, and iOS's existing offline-first queue (an iOS-only strength, kept).

## Decision

1. The picker lists CACHED roster zones whose building is also cached (P1's `RosterZones` and the Site rows), flat, labelled "<Building> · <Zone>", sorted by building then zone, unverified zones included, NOTHING preselected, Start disabled until a pick. Never offers a building.
2. The phone posts the ZONE uuid with `manual: true`. A building id is never posted by a manual start.
3. iOS asks the server FIRST, with ONE client_uuid and ONE start time fixed before the request. A refusal - 409 `shift_already_open`, 422 `zone_unverified` / `unknown_location` / `tag_unbound`, 401, any other 4xx except 408 and 429 - is shown INSIDE the sheet in the worker's words (`APIFailure.workerMessage`), writes NO local row, and leaves the sheet open and Start usable again.
4. Only a transport failure, 408, 429 or 5xx falls back to iOS's existing local-first queue, REUSING the same client_uuid and start time, so the retry from the sync queue can never open the shift twice (the server's own idempotency on client_uuid: 201 new, 200 duplicate).
5. If a shift is already open locally, the answer 409 `shift_already_open` is given inline without a request.
6. UNCHANGED: the `manual` flag and what the office sees (decision-56 section 2), the confirmation dialog (now naming the zone label), and manual STOP (decision-56 section 3). A tag tap is untouched and remains `handleTap`'s only caller on the tap path.
7. Copy says "zone" and is taken from Android (formal "Sie") for the new strings; the operator's `BuildingPicker` keeps its own "Building" / "Choose a building" keys.

## Consequences

- A manual start on iOS works against the current server again, and a refused one tells the worker why at the moment they are looking, instead of hours later on a blocked row.
- A success is written locally AFTER the server accepted it. The sync pass then re-posts the same client_uuid and gets 200 duplicate - one extra, harmless request - which keeps `handleTap` the single write path.
- Rows already blocked in the field stay blocked: there is no automatic retry and no migration.
- The wording of "Another shift is still running - finishing it first." is untrue for a refused manual start; it is reused for parity with Android and noted as a known gap.
- The DEBUG mock stays as it is; it is re-pointed to offer ONE mock zone built from its canned building so the armed mock still walks. It cannot show a refusal: that needs a real server (see the epic's verification task).
