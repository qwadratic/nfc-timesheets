---
id: TASK-38
title: Offsite destination for the nightly pg_dump
status: Done
assignee: []
created_date: '2026-08-04 17:45'
updated_date: '2026-08-12 05:06'
labels:
  - ops
  - backup
  - payroll
  - merged
milestone: m-5
dependencies: []
priority: high
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The nightly dump works and lands on the SAME DISK as the database it is protecting. One disk failure loses the database and every backup of it at the same instant.

ops/backup/pg-backup.sh:67 carries a clearly marked TODO(offsite) hook, with an rclone example already written at line 73. Nothing has been chosen or wired.

The owner has marked this LOW priority - filed as such, deliberately not escalated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An offsite target chosen and credentials placed on the VM (rclone.conf or equivalent)
- [ ] #2 TODO(offsite) in ops/backup/pg-backup.sh resolved, not just commented
- [ ] #3 The offsite copy restore-tested by pulling it BACK DOWN: DUMP=... ops/backup/restore-test.sh
- [ ] #4 ops/README.md line 175 checklist item ticked
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MERGED INTO task-57 (2026-08-12 audit). task-57 covers this task's offsite destination PLUS the two gaps it missed: the restore has never actually been executed, and ops/systemd/nfc-backup.service has no EnvironmentFile, so the offsite work as documented aborts on first run under set -u. Do the work on task-57.
<!-- SECTION:NOTES:END -->
