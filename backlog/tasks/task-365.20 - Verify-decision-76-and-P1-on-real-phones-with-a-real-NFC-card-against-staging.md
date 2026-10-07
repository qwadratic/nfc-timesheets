---
id: TASK-365.20
title: Verify decision-76 and P1 on real phones with a real NFC card against staging
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - android
  - verification
dependencies:
  - TASK-365.2
parent_task_id: TASK-365
priority: high
ordinal: 304000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nothing in decision-76 or P1 has been driven with a physical card. The simulator walk used the DEBUG mocks for radio and network; Android was only compiled and checked.

## Walk (one iPhone and one Android phone, staging API, one operator and two workers)
1. Write a card, leave the Write screen WITHOUT creating the zone. Tap it as a worker: expect the tag_unbound sentence (iOS and Android).
2. Test a tag -> scan that card: expect the finish form; name + building -> "Verified. This door is now a clock-in target." Tap as a worker: shift opens, building name shown.
3. Same with Skip: zone exists, unbound, building picker offered, NOT verified.
4. Write a card with a building: hint + Activate this card -> Test a tag with the zone preselected -> scan -> verified.
5. Create a zone, then WITHOUT pull-to-refresh tap it on a worker phone that already has an older roster: the shift shows the building name within one roster round trip; tapping a second zone of the same building closes the shift.
6. Send a material request during a zone-started shift: 201, building attached.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Steps 1-6 driven on both platforms with a physical card; results and screenshots attached
- [ ] #2 Any divergence filed as its own task
<!-- AC:END -->
