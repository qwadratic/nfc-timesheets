---
id: TASK-365
title: 'iOS worker parity with Android PRs 3-7 (8aafbf1..60f6886): epic'
status: To Do
assignee: []
created_date: '2026-10-07 12:20'
updated_date: '2026-10-12 09:42'
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

decision-80 (2026-10-07): the iOS worker app shows the signed-in worker's planned assignments, read-only and display-only (amends decision-73 and docs/product-launch-and-scheduling.md line 36). This is the planned 'decision-78' of P4 (TASK-365.5); 77 and 78 belong to branch admin-declutter. Recorded BEFORE the P4 code.

DECISION RENUMBER (2026-10-12): the manual-start decision recorded as decision-79 in TASK-365.3 / .7 / .22 and in this epic is decision-81 (79 was taken on main by the agent-integration decision, Company-bound agent REST and stdio MCP). Read "decision-79" in those tasks as 81. The decision file was renumbered before the merge of origin/main; its text is unchanged.

MERGE origin/main (aca52e1) into ios-worker-parity, 2026-10-12 (merge commit 9bf941b; decision renumber 79 -> 81 committed first as 1a74483). PR 17 shift evidence (periodic location + camera proof of work; Android, iOS, server, web) landed on main from another author (Kigulx) together with PR 16 agent integration, and its iOS half had never been compiled or driven (written on a Windows host). Conflict resolutions: Sync.swift - the worker guard stays inside pushClose (TASK-365.4), main loop-level guard dropped as redundant, main pendingEvidenceEnd kept; Localizable.xcstrings - JSON union, 319 keys (305 mine + 14 main), no key changed on both sides; ContentView.swift - both sides kept, main reads of the device-wide shifts moved onto WorkerScope (openRow / allShifts.openShift(for:)). Semantic fixes where evidence met this branch: (1) the proof gate (LogView.prepareCompletion) holds a FINISH only for a shift KNOWN to require proof; main original awaited the network and refused the tap with Connect to the internet when the policy was unknown - now that finish runs local-first and the server enforces (422 proof_required reopens the row; Sync.record also clears autoClosed/manualClose). Android still has main original behaviour (TimeSheetViewModel.handleTap/confirmedShift), NOT changed here - owner call. (2) main used shifts.contains(where: isOpen) in handleTap, which with a shared phone would have swallowed worker B tap behind worker A open row (P3 bug) - now openRow. (3) the gate switched flag compared raw place ids (re-introducing the decision-43 second-door bug) - now one rule, leavesBuilding(). Text pins updated in the same commit, none deleted or loosened: worker-scope-check (manualStop assertion moved to finishManualStop, +hand-off and gate-scope pins), shift-signal-check (manualStop body assertions re-targeted to finishManualStop; new pins for the gate, handleTap pre-save branch, record() reopen, location off the tap/sync/signal paths). Still open: no driven walk of the proof or location flows on a simulator or phone (camera, background location, 422 reopen, switch with proof); a known-required finish needs camera + network by design on both platforms, which is in tension with the local-first tap invariant - owner decision; docs/shift-evidence.md still states the old unknown-policy rule for both platforms.
<!-- SECTION:NOTES:END -->
