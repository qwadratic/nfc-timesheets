---
id: decision-84
title: >-
  The backlog branch may carry exactly one non-backlog file: the push-triggered
  gate workflow (TASK-372)
date: '2026-10-14 08:51'
status: accepted
---
## Context

AGENTS.md rule 3 said nothing outside `backlog/` is ever committed to the `backlog` branch. A push to that branch cannot run a workflow that lives on main, so the branch was re-checked by a 20 minute cron. A GitHub ruleset with `file_path_restriction` would block a bad push instead, but GitHub answers 422 for it on a user-owned repository (checked 2026-10-14).

## Decision

Owner, 2026-10-14: the branch may hold exactly one file outside `backlog/`: `.github/workflows/backlog-gate-push.yml`. It runs on `push` to `backlog`, fetches `ops/backlog-guard.sh` from `origin/main` and runs `branch HEAD`. The guard comes from main, so a commit on the backlog branch cannot weaken it. An identical copy of the workflow also lives on main so that `git merge origin/backlog` stays a no-op for it.

## Consequences

- `ops/backlog-guard.sh` allows `backlog/**` plus that one path and nothing else.
- The 20 minute schedule in `backlog-gate.yml` becomes a daily net.
- Editing the workflow file on the backlog branch is the one remaining way to weaken the check; the diff of that file is the review point.
