---
id: TASK-60
title: 'Deploy gets a build id, a health gate and one-command rollback'
status: To Do
assignee: []
created_date: '2026-08-12 05:03'
labels: []
milestone: m-6
dependencies: []
priority: medium
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ops/deploy.sh:12 says it outright: no build-id, no rollback, no health gate beyond the curl at the end.

rsync -az --delete (:66,:73,:74) overwrites in place - the previous artifact is DESTROYED, there is nothing on the box to go back to. Migrations apply at :86 and the process restarts at :90, so between those two lines the OLD code runs against the NEW schema. :90 is systemctl restart - a hard bounce, no drain. For a worker standing at a door with a phone against a tag, that window is the product. The post-deploy check is sleep 2 plus systemctl is-active: liveness, not readiness. /health is never called.

Nothing on the box says which commit is running, and git tag is empty (0 tags), so there is no name for what shipped either. task-41 shows the cost - it has to reconstruct what is unshipped by listing seven commit SHAs by hand.

Doc drift: ops/README.md:59 says chown -R app:app; ops/deploy.sh:82 does chown -R exedev:app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release directories /srv/nfc/releases/<git-sha>/ with a current symlink; keep 5; rollback is one ln -sfn plus restart
- [ ] #2 Deploy writes the git SHA to the box and /health reports it, so what is running is answerable without SSH
- [ ] #3 Deploy calls /health after restart and FAILS on non-200
- [ ] #4 Expand migrations (additive) run before restart; contract migrations only after
- [ ] #5 Migrations gain a checksum column (refuse to start if an applied file changed) and a pg_advisory_lock, per server/db/migrate.js:12-16
- [ ] #6 ops/deploy.sh takes a pg_dump immediately before migrating and prints the restore command
- [ ] #7 git tag on every deploy; CHANGELOG.md adopted
- [ ] #8 chown drift between ops/README.md:59 and ops/deploy.sh:82 reconciled
- [ ] #9 DEMO: deploy, break something, roll back with one command, show /health reporting the previous SHA
<!-- AC:END -->
