---
id: TASK-102
title: 'Surprise 2: the watchlist - pin a question, get told when it becomes true'
status: To Do
assignee: []
created_date: '2026-08-12 06:04'
labels:
  - assistant
dependencies:
  - TASK-100
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design doc §9.2. The feature that turns a chat into an operations manager: the director's second
week is the same five questions as their first, and this is the difference between ANSWERING them
and BEING TOLD.

Any tier-A question can be pinned ('sag mir, wenn in der Stiftgasse mehr als 12 Stunden in einer
Woche stehen'), storing the (capability, params, threshold) triple. Evaluated by the SAME nightly job
as TASK-100 — one table, one loop, no new machinery. ZERO model calls on the evaluation path,
because a threshold comparison is '>'.

Surfaces on / only when the condition is TRUE. Guardrails against becoming noise:
- five per tenant, hard cap
- auto-expiry after 60 days unless re-confirmed
- each alert carries the 'Nachrechnen' link so it can be checked in one click

Only tier-A capabilities are pinnable. A pinned mutation would be an action running unattended,
which is exactly what decision-36 §2 forbids.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Only tier-A capabilities can be pinned; a test proves a tier-B pin is refused
- [ ] #2 Evaluation makes zero model calls; a fetch interceptor proves it
- [ ] #3 Cap of 5 per tenant enforced server-side, not only in the UI
- [ ] #4 Auto-expiry after 60 days; expired watches surface for re-confirmation rather than vanishing
- [ ] #5 Every alert carries a Nachrechnen link with an absolute from/to range
<!-- AC:END -->
