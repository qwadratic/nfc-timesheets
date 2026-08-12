---
id: TASK-126
title: 'Voice-call fallback: when the SMS does not arrive, the code is read aloud'
status: To Do
assignee: []
created_date: '2026-08-12 06:14'
labels:
  - server
milestone: m-6
dependencies:
  - TASK-123
documentation:
  - backlog/docs/SMS-AUTH.md
priority: low
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH section 7 item 3, implementation step 11. One more Twilio endpoint against the SAME
challenge row - not a second challenge, not a second code.

Delivery failure is a normal path, not an exception: resend 60s -> resend 120s -> voice call ->
queued tap -> break-glass code. Only the last rung needs the director.

JOB: JTBD #3 and the "did the tap land" job - a worker who cannot sign in cannot clock in.

MUST NOT REGRESS: the same per-number rate limits and the same process-wide spend cap apply. A
voice call costs more than an SMS; it must count against the same budget, not a fresh one.

PARALLEL after TASK-123.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 POST /auth/sms/voice reuses the existing challenge row - a check asserts no second challenge is created
- [ ] #2 Voice calls count against the same per-number and process-wide budgets as SMS; a check proves the counter increments
- [ ] #3 The German the code is read in is intelligible over a bad line: digits spoken singly, with a pause, repeated once
<!-- AC:END -->
