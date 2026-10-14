---
id: TASK-372
title: >-
  Push-triggered gate: one workflow file on the backlog branch runs
  backlog-guard on every push to it
status: Done
assignee: []
created_date: '2026-10-14 07:53'
updated_date: '2026-10-14 08:55'
labels:
  - ci
  - process
dependencies: []
priority: medium
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner decision 2026-10-14 (option B). GitHub rejects the file_path_restriction ruleset rule on a user-owned repo (422), so a push to the backlog branch is checked by a workflow that lives ON that branch: exactly one allowed non-backlog file, .github/workflows/backlog-gate-push.yml, which fetches ops/backlog-guard.sh from main and runs 'branch HEAD'. The guard is taken from main, so a pushed commit cannot weaken it. The 20-minute cron in backlog-gate.yml becomes a daily net.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ruleset on refs/heads/backlog restricts file paths to everything except backlog/** (file_path_restriction patterns proven on a throwaway branch: push of a non-backlog file rejected, push of backlog/** accepted)
- [x] #2 Ruleset active on qwadratic/nfc-timesheets, no bypass actors; the normal backlog worktree push still works
- [x] #3 backlog-gate.yml schedule reduced from every 20 minutes to once a day; AGENTS.md rule 5 updated
- [x] #4 ops/backlog-guard.sh allows exactly one path outside backlog/ (.github/workflows/backlog-gate-push.yml), proven RED on any other path and GREEN on that one with temp refs,Workflow .github/workflows/backlog-gate-push.yml (identical copy on main and on the backlog branch) runs on push to backlog and runs the guard script taken from origin/main,RED proven in real CI on a throwaway branch (non-backlog file pushed) and GREEN on a real push to the backlog branch,backlog-gate.yml schedule is daily; AGENTS.md rules 3-5 name the one allowed file
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DONE 2026-10-14 (main 8e4269c, backlog 34f7dae). ruleset file_path_restriction is rejected (422) on user-owned repos, so option B (decision-84): .github/workflows/backlog-gate-push.yml sits on the backlog branch (and identically on main), fetches ops/backlog-guard.sh from origin/main and runs 'branch HEAD'. Guard allows backlog/** plus that one path. Proof: local temp refs RED on evil.txt and on another workflow file, GREEN on the allowed file; real CI RED run 38538346074 on throwaway branch gate-test-372 (evil.txt reported, branch deleted); real CI GREEN run 38538475812 on the push of the workflow to the backlog branch. backlog-gate.yml cron is now daily (17 4 * * *). AGENTS.md rules 3 and 5 updated.
<!-- SECTION:NOTES:END -->
