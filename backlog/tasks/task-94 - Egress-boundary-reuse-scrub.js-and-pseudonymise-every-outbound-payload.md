---
id: TASK-94
title: 'Egress boundary: reuse scrub.js and pseudonymise every outbound payload'
status: To Do
assignee: []
created_date: '2026-08-12 06:02'
labels:
  - assistant
  - security
  - privacy
dependencies:
  - TASK-92
references:
  - backlog/decisions/decision-36.md
  - server/lib/scrub.js
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: high
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The channel everybody forgets: the prompt is egress. Every row the assistant reads and puts in
context LEAVES THE VM to the model provider. Read-only-ness does not touch this.

server/lib/assistant/egress.js — the single funnel (design doc §4.4):
1. Reuse scrub.js SECRET_KEY_RE VERBATIM. Do not re-type the denylist. That file's header already
   argues why two copies are two chances to get it wrong; this is the second boundary it awaited.
2. Per-conversation pseudonymisation: workers.name -> MA-1.., locations.name/address -> OBJ-1..,
   clients.name -> KD-1.. Substituted back on return for display.
   ponytail: a Map + two replaceAll passes over the JSON before stringify. Ceiling: a name the
   DIRECTOR typed by hand is not aliased (only DB-sourced values are known to be names).
   Upgrade path: word-boundary match of the alias table against the question text.
3. Caps: 200 rows / 32 KB per capability result. Over the cap the assistant is TOLD the count and
   the truncation and must say so — never silently reason over the first 200 of 4,000.
4. Named exception, stated not hidden: the e-mail-draft capability un-aliases recipient name and
   building only, and the UI says so before generation. Wage figures are NEVER un-aliased.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One funnel: no code path reaches the provider without passing egress.js
- [ ] #2 V9: intercept globalThis.fetch on a fixture with known values; assert no worker name, building name, e-mail or phone number appears in any outbound payload
- [ ] #3 V9 goes RED with the pseudonymiser removed — RED output pasted into notes
- [ ] #4 Row/byte caps produce an explicit truncation fact in context, and a test asserts the answer mentions it
- [ ] #5 scrub.js is imported, not duplicated; a test fails if the denylist is re-declared in egress.js
<!-- AC:END -->
