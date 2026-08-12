---
id: TASK-112
title: >-
  The installed systemd unit is not the one in the repo - Sentry has no --import
  and nothing notices
status: To Do
assignee: []
created_date: '2026-08-12 06:10'
updated_date: '2026-08-12 06:14'
labels:
  - ops
  - telemetry
milestone: m-5
dependencies: []
documentation:
  - backlog/docs/UX-AUDIT.md
modified_files:
  - ops/systemd/nfc-api.service
priority: high
ordinal: 1700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 5, second half. TASK-44 covers the missing SENTRY_DSN. This covers the other
failure, which would keep Sentry blind even after the DSN lands:

    systemctl cat nfc-api        ->  ExecStart=... node server.js
    ops/systemd/nfc-api.service  ->  ExecStart=... node --import ./instrument.mjs server.js

The repo file even carries the comment "--import is REQUIRED, not a style choice ... Dropping the
flag silently loses all tracing." The flag was dropped anyway, on the one machine that runs payroll,
and no check compares the two.

THE GENERAL BUG is not the flag, it is that a unit file in git and a unit file on the VM are allowed
to differ silently. Fix the general bug: a check that diffs installed against repo.

JOB: none directly - this is the instrument that tells you WHY the pilot ran once and stopped.
That question is currently unanswerable, which is why it is high.

MUST NOT REGRESS: decision-23 - telemetry must never be required to boot and must never block a
clock-in. A drift check must not become a boot dependency. If instrument.mjs cannot load, the API
still serves /t.

PARALLEL: yes. Related to TASK-44 (DSN) and TASK-60 (deploy build id + health gate) - if TASK-60 is
scheduled, fold the drift check into its health gate rather than building a second one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A check compares the installed unit against ops/systemd/nfc-api.service and fails on any difference; it runs in deploy and can be run by hand
- [ ] #2 Mutation proof: strip --import from a copy of the unit -> RED. Paste the RED output
- [ ] #3 The installed unit carries --import ./instrument.mjs after the next deploy, verified with systemctl cat, not with the repo file
- [ ] #4 A deliberately thrown error reaches Sentry from the running service - the end-to-end proof, not the config check
- [ ] #5 Boot with instrument.mjs unloadable still serves POST /t successfully (decision-23 gate)
<!-- AC:END -->
