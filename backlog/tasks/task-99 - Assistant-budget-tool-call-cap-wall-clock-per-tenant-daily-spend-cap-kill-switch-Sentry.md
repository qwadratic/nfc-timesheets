---
id: TASK-99
title: >-
  Assistant budget: tool-call cap, wall clock, per-tenant daily spend cap, kill
  switch, Sentry
status: To Do
assignee: []
created_date: '2026-08-12 06:04'
labels:
  - assistant
  - ops
dependencies:
  - TASK-96
references:
  - backlog/decisions/decision-36.md
  - backlog/decisions/decision-23.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
server/lib/assistant/budget.js. Every limit fails CLOSED (design doc §8).

- <= 4 tool calls per turn. The fifth is a refusal, not a loop.
- 30 s wall clock per turn. 3 s statement_timeout per query (already on the role, TASK-92). max:2 reads.
- Token cap per turn.
- Per-tenant DAILY spend cap in app_settings: assistant.daily_cap_millicents, default 200 (= 2 EUR/day).
  Over cap => a plain German sentence ('Das Tageslimit fuer den Assistenten ist erreicht.'), never a
  spinner and never a silent degradation to a worse answer.
- NOTHING MAY RAISE ITS OWN BUDGET: POST /admin/settings and DELETE /admin/settings/:key are tier D
  (decision-36 §2).
- Kill switch: ASSISTANT_ENABLED absent => inert, per decision-23's shape. Costs are recorded in
  assistant_audit.cost_millicents on every turn including refusals.
- Sentry: verifier fallbacks (TASK-100) and provider errors raise events; scrub.js already covers the
  payload. Telemetry must never be required to boot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V12: over the daily cap the turn is refused with the German sentence and ZERO provider calls. RED when the budget check is removed
- [ ] #2 The 5th tool call in a turn is a refusal row, not a loop; a test proves it terminates
- [ ] #3 cost_millicents is written on every turn, including refused and failed ones
- [ ] #4 app_settings assistant.* keys cannot be written by any capability; a test proves the tier-D refusal
<!-- AC:END -->
