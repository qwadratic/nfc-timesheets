---
id: TASK-96
title: >-
  Assistant chat route and drawer: German, 390px, accessible, inert without
  ASSISTANT_ENABLED
status: To Do
assignee: []
created_date: '2026-08-12 06:03'
labels:
  - assistant
  - web
  - a11y
dependencies:
  - TASK-93
  - TASK-94
references:
  - backlog/decisions/decision-36.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
server/routes/assistant.js (auth:'admin') + lib/assistant/loop.js, plus the panel drawer.

Constraints that are not negotiable:
- decision-23 restated with a second subject: the assistant must never be required to boot and must
  never sit on the path of a clock-in. ASSISTANT_ENABLED absent => /admin/assistant/* is 404 and
  the process is otherwise identical. routes/app.js imports nothing from lib/assistant/.
- decision-16: output:'export'. Client component, one endpoint, no dynamic route, no server component.
- Zero new dependencies. The provider is reached with global fetch (Node >= 22). No LLM SDK.
- decision-8/17: German default, de.json/en.json EXACT key parity, no bare JSX literals.
- decision-29: works at 390px. The drawer is full-height on a phone, not a squeezed desktop panel.

ponytail: one turn = one request/response. No streaming, no websocket, no job queue.
Ceiling: a 6 s answer shows a spinner for 6 s. Upgrade path: text/event-stream on node:http,
still zero dependencies, once someone actually complains.

Progress line derived from the capability names ACTUALLY running ('Ich sehe die Schichten vom
1.-31. Juli durch ...'), never invented.

Accessibility: keyboard-operable end to end, aria-live='polite' on the answer region (never
assertive), focus returns to the question box after an answer, and the drawer traps focus while
open. Accessibility is not traded for polish.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V10: ASSISTANT_ENABLED unset => /admin/assistant/* 404, process boots, a clock-in succeeds. RED when boot is made to depend on the assistant module
- [ ] #2 V11: intercept fetch, load all 7 admin routes, assert ZERO provider calls. RED when the dashboard handler calls the provider
- [ ] #3 V15: de/en key parity for every new key; pnpm check RED when a key is added to de.json only
- [ ] #4 Keyboard-only walkthrough recorded: open, ask, read, approve-target focus, close
- [ ] #5 Renders correctly at 390px; no horizontal scroll
- [ ] #6 Provider failure reads as the ASSISTANT failing, not the panel failing
<!-- AC:END -->
