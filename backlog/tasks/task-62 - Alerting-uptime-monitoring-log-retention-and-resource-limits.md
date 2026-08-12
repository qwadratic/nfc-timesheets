---
id: TASK-62
title: 'Alerting, uptime monitoring, log retention and resource limits'
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-5
dependencies:
  - TASK-44
priority: medium
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extends task-44 (which covers only the Sentry DSN). Nothing watches anything.

NO alerting of any kind: OnFailure= is absent from all 5 systemd units. A failed nightly pg_dump produces a red systemctl status nobody is looking at.

NO uptime monitoring: /health exists (server/server.js:54,:61-64) and NOTHING polls it - not even ops/deploy.sh.

NO resource limits or watchdog on any unit: no MemoryMax, CPUQuota, TasksMax, LimitNOFILE, WatchdogSec. nfc-api.service:32-33 is Restart=always/RestartSec=5 with no StartLimitBurst override, so systemd's default gives up after 5 restarts in 10s and leaves the unit FAILED, silently.

Log retention is journald defaults, unconfigured - no journald.conf, no SystemMaxUse=. The auto-close audit record (ops/sql/autoclose.sql:19-20) exists NOWHERE ELSE by design, so log rotation destroys it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OnFailure= alert units on nfc-backup.service and nfc-api.service
- [ ] #2 An external uptime monitor polls /health
- [ ] #3 journald SystemMaxUse= pinned so the auto-close audit record survives
- [ ] #4 MemoryMax and StartLimitBurst set on nfc-api.service
- [ ] #5 DEMO: kill the API process and show the alert arriving; fill the disk and show the backup failure alerting
<!-- AC:END -->
