---
id: TASK-371
title: >-
  CI gate for the backlog branch: only backlog/** there, main's backlog/ is a
  mirror, referenced ids exist
status: To Do
assignee: []
created_date: '2026-10-13 05:40'
updated_date: '2026-10-13 05:43'
labels:
  - ci
  - backlog
  - process
dependencies: []
priority: high
ordinal: 309000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner request 2026-10-13. The rule 'record FIRST on the backlog branch' (AGENTS.md) is enforced by a GitHub Actions workflow on main plus a script ops/backlog-guard.sh that the workflow, a human and an agent can all run.

Checks: (1) BRANCH: origin/backlog contains only backlog/** in its tree AND in every commit's changed paths; (2) MIRROR: the backlog/ tree of the commit under test (main push, PR merge ref, any work branch) equals the backlog/ tree of SOME commit in origin/backlog's history, i.e. no data reaches the regular backlog from another branch; (3) IDS: every TASK-N / decision-N cited in the commit messages of the pushed range or PR exists on origin/backlog.
Triggers: push to main, pull_request to main, schedule (20 min, because a push to backlog cannot run a workflow that lives on main), workflow_dispatch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ops/backlog-guard.sh has modes branch, mirror and ids and exits non-zero with a readable message on a violation
- [x] #2 Each mode is proven RED by a synthetic violation (a non-backlog file on a temp backlog ref, an edited backlog/ file on a temp work ref, an unknown TASK id) and GREEN on the real refs
- [x] #3 Workflow .github/workflows/backlog-gate.yml runs the three checks on push to main, pull_request to main, a 20 minute schedule and workflow_dispatch
- [x] #4 The workflow is GREEN on main after it lands, and the schedule/dispatch run is observed
- [x] #5 AGENTS.md names the gate and how to run the script locally
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DONE 2026-10-13 (main c60fabc). ops/backlog-guard.sh: modes branch / mirror / ids / all; refs are resolved to SHAs because a branch called backlog and a directory called backlog/ are ambiguous to git. Proven RED locally with temp refs (non-backlog file on a temp backlog ref, edited backlog/ on a work ref, unknown TASK/decision id) and GREEN on real refs and on a 'Backlog-exempt:' commit. Proven RED in REAL CI through a throwaway PR (#1, closed, branch deleted): mirror step AND ids step both failed in the same run (always()), branch step passed. GREEN on push to main and on workflow_dispatch; the 20-minute schedule exists but its first scheduled run was not yet observed when this was written. A push to the backlog branch itself cannot run a workflow living on main, hence the schedule + checks on every main push/PR.
<!-- SECTION:NOTES:END -->
