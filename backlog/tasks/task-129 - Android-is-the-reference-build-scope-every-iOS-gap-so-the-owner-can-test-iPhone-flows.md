---
id: TASK-129
title: >-
  Android is the reference build: scope every iOS gap so the owner can test
  iPhone flows
status: To Do
assignee: []
created_date: '2026-08-12 11:19'
labels:
  - ios
  - parity
  - scoping
dependencies: []
priority: high
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DECISION EMBEDDED IN THIS TASK: Android is now the REFERENCE implementation and iOS is behind. Every feature difference is scoped as iOS work to close, not as an Android feature to justify.

WHY iOS FELL BEHIND, factually: the last TestFlight build is build 4. Everything since has
landed only on Android or the server - the in-shift lock and cross-platform signals (commit
ba031bf), the manual tag scan and serial adoption (which Android got as v1.2/v1.3 APKs), and
whatever the UX work implies for the phone. task-41 already covers CUTTING a build; this task
is about knowing WHAT should be in it before it is cut.

DELIVERABLE: a gap table. One row per feature, columns: Android state / iOS state / is the
difference GENUINE platform capability or just unbuilt / what iOS needs / effort (low-med-high
with a reason, no time estimates).

Known starting points, to verify rather than trust - the file that claims parity may itself be
stale:
  - manual tag scan. Android has nfc/ScanActivity.kt with reader mode plus KnownTags serial
    adoption. iOS has NOTHING: the in-app scanner was DELETED (commit e4ac6e2) after App Store
    error 90778, because NDEF is disallowed in the readersession formats key against the iOS
    26.5 SDK. So iOS CANNOT clock out on the adopted HOIV tag AT ALL. This is the single
    biggest gap and it is a capability question, not a laziness question - see task-89's
    formats=[TAG] spike, which must land before anything here is promised.
  - in-shift lock: shipped in source for both, but iOS has never been on a device since.
  - Live Activity ships INERT on iOS - NSSupportsLiveActivities is set but there is no Widget
    Extension target, so Activity.request throws and is swallowed. Android has a real
    lock-screen clock. Do not report this as 'iOS has Live Activities'.
  - sign-in: decision-26 split them deliberately (Apple on iOS, codes on Android). Tasks
    124/125 supersede this with phone+SMS on both, so DO NOT scope Apple sign-in work here -
    check those tasks first and defer to them.
  - language fallback: see task-128, iOS falls back to English where Android falls back to
    German.

RULES:
  - never edit project.pbxproj. Where a change needs Xcode, write the exact click path.
  - iOS changes must stay additive and inert until the owner cuts a build; a broken iOS build
    blocks every future fix, not just this one.
  - state plainly which gaps CANNOT be closed (App Review, missing entitlement, no hardware)
    versus which are simply unbuilt. Those are different problems with different owners.

OUTPUT: backlog/docs/IOS-GAP.md plus one child task per closable gap, ordered so the owner can
test complete iPhone flows soonest - a half-closed flow is not testable.
<!-- SECTION:DESCRIPTION:END -->
