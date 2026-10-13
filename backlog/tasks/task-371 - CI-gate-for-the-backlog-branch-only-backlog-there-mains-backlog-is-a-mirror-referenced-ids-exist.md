---
id: TASK-371
title: >-
  CI gate for the backlog branch: only backlog/** there, main's backlog/ is a
  mirror, referenced ids exist
status: To Do
assignee: []
created_date: '2026-10-13 05:40'
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
- [ ] #1 ops/backlog-guard.sh has modes branch, mirror and ids and exits non-zero with a readable message on a violation
- [ ] #2 Each mode is proven RED by a synthetic violation (a non-backlog file on a temp backlog ref, an edited backlog/ file on a temp work ref, an unknown TASK id) and GREEN on the real refs
- [ ] #3 Workflow .github/workflows/backlog-gate.yml runs the three checks on push to main, pull_request to main, a 20 minute schedule and workflow_dispatch
- [ ] #4 The workflow is GREEN on main after it lands, and the schedule/dispatch run is observed
- [ ] #5 AGENTS.md names the gate and how to run the script locally
<!-- AC:END -->
