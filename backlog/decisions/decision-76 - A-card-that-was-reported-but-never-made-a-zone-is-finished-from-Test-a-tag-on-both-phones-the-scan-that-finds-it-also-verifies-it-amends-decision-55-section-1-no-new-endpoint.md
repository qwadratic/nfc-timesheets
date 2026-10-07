---
id: decision-76
title: >-
  A card that was reported but never made a zone is finished from Test a tag on
  both phones; the scan that finds it also verifies it - amends decision-55
  section 1, no new endpoint
date: '2026-10-07 10:45'
status: accepted
---
## Context

Found on the staging server on 2026-10-07, from its request log and its database, while
chasing "the zone I just created does not read".

- Card `a84797f8` was written and reported (`POST /operator/tags`, 10:15:50) and the zone
  step was opened (`GET /operator/locations` followed), but `POST /operator/tags/:id/
  resolve-zone` was never sent. The card has been a `reported_tags` row with no zone ever
  since. Every tap of it - workers 119 and 120 on the worker app, and three operator test
  scans (`/operator/zones/:id/verify`) - answers `422 tag_unbound`, which is correct.
- Card `2af85cdc` ("4 floor", building HOIV) went through write, resolve-zone (10:35:32) and
  a test scan (`verify` 200, 10:36:05), and worker 119 opened and closed a shift on it at
  10:36:25. The server, deployed byte-for-byte equal to the repository, was right about both.

So "new zone is not read" was a card stranded half-way, plus an operator who had no way to
finish it. decision-55 §1 says of exactly this state (`{kind: "tag_reported"}`): "No action
is offered from this screen; resolving a report into a zone stays `POST
/operator/tags/:id/resolve-zone`, reached the way it always was." That way is the Write
screen's in-memory zone step, and it is gone the moment the operator leaves the screen, taps
"Write another card", or the app is killed. Nothing else in either app ever calls
resolve-zone. A reported card with no zone is unrecoverable except by writing a new card on
top of it, and nothing on screen says so.

Two smaller gaps sit on the same path, and iOS has both (Android shipped the cures in PR 7):

- after "Create zone" with a building, iOS says only "Zone created", not that the zone is not
  a clock-in target until it is test-scanned (decision-47), so a worker's next tap is refused
  `zone_unverified` and the operator concludes the zone is broken;
- a worker tapping an unzoned card sees iOS's generic "Rejected by the server
  (tag_unbound)", where Android says the tag is not assigned to a building yet.

## Decision

1. FROM TEST A TAG, A CARD THAT CLASSIFIES AS `tag_reported` OFFERS THE ZONE STEP. The same
   fields as the Write screen's zone step - a zone name and a building (Skip allowed, an
   unbound zone is still a legitimate resting state, decision-54 §1) - and the same existing
   call, `POST /operator/tags/:id/resolve-zone`, with the id that was just read off the card.
   This amends decision-55 §1 and nothing else in it.
2. THE SCAN THAT FOUND THE CARD IS ITS TEST SCAN. When resolve-zone succeeds and a building
   was chosen, the phone immediately calls the existing `POST /operator/zones/:id/verify`
   with the same id it just read. An operator standing at the door with the card in hand
   has done exactly what decision-47 asks, and making them scan it a second time to prove the
   same bytes proves nothing new. A zone created WITHOUT a building is not verified (nothing
   resolves it yet, decision-47/55); it says so and offers the building picker the existing
   unbound-zone page already has.
3. THE WRITE SCREEN SAYS THE TEST IS STILL OWED. On a zone created with a building, both
   phones say that one test is still needed before workers can clock in, and offer one
   button straight to that zone's test screen, preselected (Android has this since PR 7; iOS
   gets it). Writing a card still never activates a zone.
4. A WORKER TAPPING AN UNZONED CARD IS TOLD WHAT IS TRUE. iOS maps `422 tag_unbound` to the
   same sentence as Android's `err_tag_unbound`, in both languages. It stays terminal.
5. ZERO new server endpoints and no server change. resolve-zone already refuses a card that
   is not a reported, unresolved tag (404 `unknown_reported_tag`, 409 `already_resolved`),
   so a second operator racing this one, or a stale screen, gets a sentence and nothing
   changes. The phone mints no id here: the id is always read off a card.
6. Everything that decision-47 gates stays gated: this decision adds no way for a zone to
   become verified without a scan of its own card, and the verify call's own check (the
   scanned id must BE the zone) still applies.

## Consequences

- A card that is written and reported but never zoned stops being a dead end. The operator
  taps Test a tag, holds the card, names the door, picks the building, and is done in one
  visit.
- Resolve-zone and verify are two requests. If the second fails after the first succeeded,
  the zone exists unverified and the screen says so and offers the ordinary test scan;
  nothing is rolled back and nothing is lost.
- The classification sentence for `tag_reported` changes from "nobody has made it a zone yet"
  to an invitation to do it.
- The same facts apply to both phones, so both get a check (iOS `checks/`, Android
  `checks/`) pinning the order resolve-zone, then verify with the SAME scanned id, and the
  rule that Skip produces no verify call.

