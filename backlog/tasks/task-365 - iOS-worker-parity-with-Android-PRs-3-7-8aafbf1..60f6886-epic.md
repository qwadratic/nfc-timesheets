---
id: TASK-365
title: 'iOS worker parity with Android PRs 3-7 (8aafbf1..60f6886): epic'
status: To Do
assignee: []
created_date: '2026-10-07 12:20'
updated_date: '2026-10-07 12:27'
labels:
  - ios
  - parity
  - worker
  - epic
dependencies: []
priority: high
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Android and iOS were kept in sync until 8aafbf1. PRs 3, 5, 6 and 7 (range 8aafbf1..60f6886) changed Android, the server and the web admin and touched NOTHING under NFCTimeSheets/. This epic carries every Android change that belongs on the iOS WORKER app, in the owner's order.

## Scope rules (owner, 2026-10-07)
- WORKER in the MOBILE app: user experience. The admin web is out of scope; operator-only tools are deferred.
- The target is a real phone WITH NFC running against the main API, which is STAGING. Do NOT build a demo mode, a no-NFC mode, mock modes, fixtures, seeded-data switches or an alternate/isolated API. The existing DEBUG hooks (DemoHooks.swift, ShiftMockFlows.swift, OperatorMockFlows.swift) stay as verification tooling only.
- Port Android BEHAVIOUR AT HEAD 60f6886, not intermediate commits (PR 7 rewrote the worker flow several times).
- Work in a git worktree (ops/WORKTREES.md); never `git add -A`.

## Order
1. Done: decision-76 finish-a-reported-card (both phones) and P1 roster zones (iOS).
2. P2-P7 (tiers A, C, D): manual start picks a zone, shared-phone scoping, planned assignments, "not confirmed yet", delivery status, receipt/motion/My hours. One after another; STOP and review after P7.
3. B1-B5: the "Blue Hour" reskin of every worker screen (docs/ANDROID-WORKER-DESIGN.md).
4. E1-E3: in-app language control (decision-74) - after the reskin, because its resolver sweep touches every view.
5. Deferred / debt tasks, filed but not scheduled.

## Decisions recorded for this epic
- decision-74: iOS in-app Deutsch / English / follow-the-phone, one value shared with the OS per-app setting, live switch (supersedes decision-61 for iOS; mirrors decision-71).
- decision-76: a reported-but-never-zoned card is finished from Test a tag; the scan that finds it also verifies it (amends decision-55 section 1).
- Still to record when their task starts: decision-77 (manual start picks a ZONE and asks the server first), 78 (worker sees planned assignments), 79 (delivery wording, no promise of automatic delivery), 80 (My hours).

## Evidence base
A 12-agent read of the range produced 134 distinct behaviour items (41 PORT, 34 PARTIAL, 36 already on iOS, 17 not applicable, 3 iOS breakages, 3 blocked by decision-61 - since lifted by decision-74). Each package task below embeds its items with Android evidence (path:line at 60f6886), the iOS gap and port notes. 53 items need no work.

## Review gate (AGENTS.md)
After the implementation tasks, a dedicated review agent reads ALL backlog/decisions/, the diff, runs node ops/check-branding.mjs and NFCTimeSheets/checks/run.sh and quotes every non-ok line (check-branding prints a TODO for TASK-188: iOS still names the renameable API host).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DECISION NUMBERS (2026-10-07): the plan proposed decisions 77-80. Branch admin-declutter already holds decision-77 (retire /product) and decision-78 (web-admin SMS controls), so: manual start = decision-79 (recorded). The remaining proposals (planned assignments, delivery wording, My hours) get the next free numbers when their task starts - use backlog decision create, which assigns them, and quote the number in the task.
<!-- SECTION:NOTES:END -->
