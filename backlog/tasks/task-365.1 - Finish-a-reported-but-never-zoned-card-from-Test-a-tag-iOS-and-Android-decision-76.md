---
id: TASK-365.1
title: >-
  Finish a reported-but-never-zoned card from Test a tag, iOS and Android
  (decision-76)
status: Done
assignee: []
created_date: '2026-10-07 12:20'
updated_date: '2026-10-07 12:22'
labels:
  - ios
  - android
  - operator
  - zones
dependencies: []
parent_task_id: TASK-365
priority: high
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on staging 2026-10-07 from the server log and database: card a84797f8 was written and reported (10:15:50) but POST /operator/tags/:id/resolve-zone was never sent. Every later tap (workers 119 and 120) and three operator test scans answered 422 tag_unbound. The only caller of resolve-zone was the Write screen's in-memory zone step, gone once the operator left it, and Test a tag offered no action for tag_reported (decision-55 section 1). The other new zone, 2af85cdc ("4 floor", HOIV), went through write, resolve-zone, verify and worker 119 clocked in and out on it at 10:36:25: the server was right. The deployed API is byte-identical to the repository.

Fix (decision-76): Test a tag finishes such a card - name + building (Skip allowed) -> resolve-zone -> verify with the id read off the card. Skip makes no verify call. A verify failure after resolve is reported as created-but-untested, never rolled back. iOS additionally: Write a tag says one test is still owed and offers "Activate this card" (zone preselected in Test a tag) or "Assign a building"; workers get a real sentence for 422 tag_unbound.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Android: a tag_reported card in Test a tag offers the zone step; resolve-zone then verify (same scanned id); Skip makes no verify call
- [x] #2 iOS: same behaviour via FinishCard.swift, pinned by checks/finish-card-check.swift (three red cases reproduced)
- [x] #3 iOS: Write a tag shows the owed-test hint and Activate this card / Assign a building; FinishReportedCardUITests 4/4 on the simulator
- [x] #4 iOS: 422 tag_unbound has its own worker sentence in de and en, pinned in tag-link-check
- [x] #5 No server change and no new endpoint
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Staging evidence (read-only, 2026-10-07): API deployed byte-identical to the repo; card a84797f8 reported 10:15:50, never zoned; zone 2af85cdc created 10:35, verified 10:36, worker 119 opened and closed a shift on it at 10:36:25. decision numbers: 75 was taken by the landing-page decision, so this is 76.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Test a tag now finishes a reported-but-never-zoned card on both phones (decision-76): name + building -> resolve-zone -> verify with the scanned id; Skip makes no verify call; a verify failure after resolve is created-but-untested, never rolled back. iOS also points Write a tag at the owed test (Activate this card / Assign a building) and words 422 tag_unbound. Commits 0d4e7bd (decisions 74+76), 6495391 (android), 892de60 (ios). Verified: iOS NFCTimeSheets/checks/run.sh green (finish-card-check with three red cases reproduced), FinishReportedCardUITests 4/4 on the simulator against the loopback stub with the DEBUG mocks for radio and network, Debug and Release build; Android checks 11/11 and assembleDebug. NOT verified: any physical NFC card, the Android screens on an emulator or device, anything against staging with a real operator and card (see the verification task).
<!-- SECTION:FINAL_SUMMARY:END -->
