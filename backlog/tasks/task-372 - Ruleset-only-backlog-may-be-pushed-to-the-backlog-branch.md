---
id: TASK-372
title: >-
  Push-triggered gate: one workflow file on the backlog branch runs
  backlog-guard on every push to it
status: To Do
assignee: []
created_date: '2026-10-14 07:53'
updated_date: '2026-10-14 08:51'
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
- [ ] #1 Ruleset on refs/heads/backlog restricts file paths to everything except backlog/** (file_path_restriction patterns proven on a throwaway branch: push of a non-backlog file rejected, push of backlog/** accepted)
- [ ] #2 Ruleset active on qwadratic/nfc-timesheets, no bypass actors; the normal backlog worktree push still works
- [ ] #3 backlog-gate.yml schedule reduced from every 20 minutes to once a day; AGENTS.md rule 5 updated
- [ ] #4 ops/backlog-guard.sh allows exactly one path outside backlog/ (.github/workflows/backlog-gate-push.yml), proven RED on any other path and GREEN on that one with temp refs,Workflow .github/workflows/backlog-gate-push.yml (identical copy on main and on the backlog branch) runs on push to backlog and runs the guard script taken from origin/main,RED proven in real CI on a throwaway branch (non-backlog file pushed) and GREEN on a real push to the backlog branch,backlog-gate.yml schedule is daily; AGENTS.md rules 3-5 name the one allowed file
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-14: BLOCKED on plan. POST /repos/qwadratic/nfc-timesheets/rulesets with a file_path_restriction rule returns 422 'Invalid rule file_path_restriction' for every pattern, including a plain 'docs/**'. A deletion rule on the same ruleset body is accepted, so rulesets work; only the path rule is unavailable for a user-owned repo (qwadratic is a User, not an org). Options: (a) transfer the repo to an org, (b) allow one workflow file .github/workflows/*.yml on the backlog branch so a push to it runs the gate, (c) local pre-push hook plus the cron as the net. Cron left unchanged.
<!-- SECTION:NOTES:END -->
