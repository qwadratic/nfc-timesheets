---
id: TASK-57
title: Offsite backup with a restore that has actually been executed
status: To Do
assignee: []
created_date: '2026-08-12 05:03'
labels: []
milestone: m-5
dependencies:
  - TASK-38
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extends task-38, which covers only the offsite destination. Two further gaps found in the 2026-08-12 audit.

ops/backup/pg-backup.sh:23 sets DEST=/var/backups/nfc. Measured on the live VM, /var/backups and /var/lib/postgresql are both on /dev/root (25G). The script's own header at line 5 says A DUMP ON THE SAME DISK AS THE DATABASE IS NOT A BACKUP. The TODO(offsite) block at :66-85 has all three options (rclone, restic, rsync) commented out.

THE RESTORE HAS NEVER BEEN RUN. backlog/docs/AUTOPILOT-RUN-REPORT.md:65 says so; the date field at ops/backup/restore-test.sh:11 and ops/README.md:108 is empty. And restore-test.sh only restores into a throwaway scratch DB (:22,:38-41) and refuses to touch live (:7,:24) - so there is no PRODUCTION restore runbook at all and RTO is undefined.

Dumps are gzip only, unencrypted, and contain sessions.token stored RAW - a stolen dump yields working admin sessions for up to 7 days. Use restic, not plain rclone.

BLOCKER on the unit: ops/systemd/nfc-backup.service has no EnvironmentFile, but pg-backup.sh:69-76 tells the operator to put offsite credentials in /etc/nfc/env and dereferences RESTIC_REPO under set -u. The offsite work as documented aborts on first run. ProtectSystem=strict plus a single ReadWritePaths=/var/backups/nfc will also block restic cache paths. Fix the unit FIRST.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 nfc-backup.service gains EnvironmentFile=/etc/nfc/env and the ReadWritePaths restic needs, verified by systemctl cat on the box
- [ ] #2 Offsite target configured with restic (encrypted at rest, because dumps carry raw session tokens); credential in psst, never in git
- [ ] #3 restore-test.sh executed at least once, date recorded at ops/backup/restore-test.sh:11 and ops/README.md:108, checkbox at ops/README.md:172 ticked
- [ ] #4 A PRODUCTION restore runbook exists in ops/README.md with a stated RTO
- [ ] #5 A dead-man switch alerts if the nightly backup does not complete - a failed pg_dump currently produces a red systemctl status nobody looks at
- [ ] #6 DEMO: pull the offsite backup down to a fresh scratch DB, restore it, and show a SELECT returning real shift rows
<!-- AC:END -->
