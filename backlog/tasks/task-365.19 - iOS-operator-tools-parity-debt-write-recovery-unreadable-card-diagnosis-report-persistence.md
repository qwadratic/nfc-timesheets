---
id: TASK-365.19
title: >-
  iOS: operator tools parity debt (write recovery, unreadable-card diagnosis,
  report persistence)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - parity
  - operator
  - deferred
dependencies: []
parent_task_id: TASK-365
priority: low
ordinal: 303000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator-only gaps found in the range; outside the worker scope, so deferred.

### write-fresh-recovery-unreadable-card - Unreadable card in Test a tag offers 'write a fresh tag now'  [PORT, size M, pre_existing]
- Android at 60f6886: On an Unreadable result a button arms a write (WriteGuard still refuses our own ids) -> POST /operator/tags -> name + optional building -> resolve-zone -> new zone selected. Since d27e740 (2026-08-27).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/VerifyZoneActivity.kt:311-333,575-750,1150-1164
- iOS gap: An unreadable card ends in a sentence with no action. decision-58 scopes its changes as 'Android-only' (scope statement).
- Port notes: Ask the owner whether iOS should get it. If yes: reuse OperatorTagMint.writeAndReport and resolveZone, a FreshState enum modelled on ReassignState, BuildingPicker(allowsSkip: true); mock flow for an unreadable scan.

### unreadable-card-diagnosis - Operator test scan names WHY a card was unreadable  [PARTIAL, size S, pre_existing]
- Android at 60f6886: TagLink.diagnose distinguishes Found / HostMismatch(host) / Malformed; the sentence names the foreign host, technologies and UID.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/core/TagLink.kt:80-102; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/VerifyZoneActivity.kt:1689-1696
- iOS gap: Outcome.unreadable carries no detail; TagLink.locationId collapses wrong host/path/uuid into nil.
- Port notes: Port TagLink.diagnose (Foundation-only, vectors in tag-link-check); TagReaderProbe returns .unreadable(uri:uid:); render 'This card points to %@, not %@'.

### pending-tag-report-persistence - A written-but-unreported card survives the app being killed  [PORT, size S, pre_existing]
- Android at 60f6886: PendingTagReport commits id, URI, serial and counts the moment a write verifies; WriteTagActivity restores it with 'report again'; cleared only when POST /operator/tags succeeds. Since 657995b (2026-08-20).
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/PendingTagReport.kt:30-78; android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/WriteTagActivity.kt:208-217,540-564
- iOS gap: outcome/report/id are plain @State: leaving the screen or termination between a write and a landed report loses the only record of an unreported card.
- Port notes: UserDefaults-backed store (OperatorZoneCache idiom) written on the onWritten path and cleared on reportLanded; restore into outcome/pendingId on appear (WriteTagStep derives the panel).

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app. The admin web is out of scope. The target is a real NFC phone against the main API (STAGING): no demo mode, no no-NFC mode, no mocks as a feature, no isolated API. Existing DEBUG hooks are verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886. Work in a worktree (ops/WORKTREES.md); never `git add -A`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each item either scheduled with its own acceptance criteria or closed Wont Do with a reason
<!-- AC:END -->
