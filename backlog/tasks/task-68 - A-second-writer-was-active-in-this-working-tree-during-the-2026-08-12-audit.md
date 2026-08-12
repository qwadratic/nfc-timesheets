---
id: TASK-68
title: A second writer was active in this working tree during the 2026-08-12 audit
status: To Do
assignee: []
created_date: '2026-08-12 05:14'
labels: []
milestone: m-5
dependencies: []
priority: medium
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED, NOT DIAGNOSED. Reporting because it invalidates an assumption in docs/AGENT-FLEET-PLAN.md.

During the 2026-08-12 backlog audit session, two changes appeared in this working tree that the auditing session did not make:

1. Commit e0281d5 'one command puts a local secret on the VM, and refuses to put the wrong ones there' (author qwadratic, 2026-08-12 06:44:28 +0200, adds ops/sync-secrets.sh, 70 lines) landed on branch plan/agent-fleet-2026-08-12 AFTER that branch was created at 75834a2. It is not on main.

2. 52 PNG screenshots appeared in docs/media/states/ between 06:52 and 07:08, untracked and unignored. They cover every admin screen at 390px and 1280px in empty/populated/loading/error/overlimit states - which looks like phone-width verification of the decision-29 work, i.e. plausibly the spot check task-50 wanted.

Most likely explanation: a second Claude Code session was live in the same working directory. That is not inherently wrong, but two consequences matter.

WHY THIS MATTERS FOR THE FLEET PLAN: docs/AGENT-FLEET-PLAN.md assumes a single writer per worktree. Eight lanes plus an unmodelled ninth writer on the shared main worktree would produce merges nobody planned. The plan needs either an explicit lock or a stated rule that main is quiet while the fleet runs.

WHY IT MATTERS FOR SECRETS: the screenshots are untracked, unignored, and named *-populated-*.png. task-37 exists because an unredacted client-name screenshot leaked into public git history once. These were deliberately NOT committed by the audit session, because their provenance could not be established. Someone who knows what they are should look before they are committed or deleted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Establish what produced e0281d5 and the screenshots, and whether ops/sync-secrets.sh was reviewed
- [ ] #2 docs/media/states/ inspected for real client names before being committed OR deleted - do not git add -A them
- [ ] #3 Either .gitignore docs/media/states/ or commit it deliberately with a note saying what generates it
- [ ] #4 AGENT-FLEET-PLAN.md gains an explicit concurrency rule: what may touch main while lanes are running
<!-- AC:END -->
