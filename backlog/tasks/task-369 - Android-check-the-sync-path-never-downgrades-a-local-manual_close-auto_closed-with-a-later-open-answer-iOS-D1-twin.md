---
id: TASK-369
title: >-
  Android: check the sync path never downgrades a local manual_close /
  auto_closed with a later open answer (iOS D1 twin)
status: To Do
assignee: []
created_date: '2026-10-12 17:46'
labels:
  - android
  - sync
  - payroll
dependencies: []
priority: high
ordinal: 307000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-365.22 found on iOS that applying the OPEN's answer (auto_closed=false, manual_close=false) over a local true wiped the flag before the close went up (offline manual stop / building switch arrived unflagged; decision-10 bypass). iOS fixed in Sync.swift apply() (only upwards) + checks/sync-flags-check.swift. Android's sync path was not read by the rig: check SyncWorker / store.markOpenSynced for the same overwrite and add a core check if it exists. Drive: server unreachable, tap-start, Finish-without-tag (manual) and tap at another building (switch); the close must carry manual:true / auto_closed:true.
<!-- SECTION:DESCRIPTION:END -->
