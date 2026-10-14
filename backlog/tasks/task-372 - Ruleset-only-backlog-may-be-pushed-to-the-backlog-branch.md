---
id: TASK-372
title: 'Ruleset: only backlog/** may be pushed to the backlog branch'
status: To Do
assignee: []
created_date: '2026-10-14 07:53'
updated_date: '2026-10-14 07:54'
labels:
  - ci
  - process
dependencies: []
priority: medium
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner request 2026-10-14. Replace the 20-minute cron in backlog-gate.yml (TASK-371) as the detector of a bad push to the backlog branch with a GitHub repository ruleset that rejects, at push time, any commit touching a path outside backlog/**. The cron stays as a daily safety net.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ruleset on refs/heads/backlog restricts file paths to everything except backlog/** (file_path_restriction patterns proven on a throwaway branch: push of a non-backlog file rejected, push of backlog/** accepted)
- [ ] #2 Ruleset active on qwadratic/nfc-timesheets, no bypass actors; the normal backlog worktree push still works
- [ ] #3 backlog-gate.yml schedule reduced from every 20 minutes to once a day; AGENTS.md rule 5 updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-14: BLOCKED on plan. POST /repos/qwadratic/nfc-timesheets/rulesets with a file_path_restriction rule returns 422 'Invalid rule file_path_restriction' for every pattern, including a plain 'docs/**'. A deletion rule on the same ruleset body is accepted, so rulesets work; only the path rule is unavailable for a user-owned repo (qwadratic is a User, not an org). Options: (a) transfer the repo to an org, (b) allow one workflow file .github/workflows/*.yml on the backlog branch so a push to it runs the gate, (c) local pre-push hook plus the cron as the net. Cron left unchanged.
<!-- SECTION:NOTES:END -->
