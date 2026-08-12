---
id: TASK-98
title: >-
  Tier-B proposals: the diff card, the approval record, and provenance into
  decision-30's tables
status: To Do
assignee: []
created_date: '2026-08-12 06:03'
labels:
  - assistant
  - security
  - web
  - a11y
dependencies:
  - TASK-93
  - TASK-96
references:
  - backlog/decisions/decision-36.md
  - backlog/decisions/decision-30.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: high
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The assistant has NO write path of its own. Executing a proposal calls the SAME /admin/* handler a
director's click calls — same validators, same 4xx, same audit rows. The blast radius of an approved
assistant write is exactly the blast radius of a click, and not one byte more.

The proposal card is never prose (design doc §3.2): a rendered before/after over exactly the fields
that change, plus the endpoint that will be called, plus the Lohnwirkung.
- EVERY figure on the card is computed server-side by the SAME resolver payroll uses (decision-30 §1).
  The model supplies intent ('end = 11:45'); it never supplies a euro amount. A money figure the model
  typed is not shown anywhere in this product.
- 'Ausfuehren' is DISABLED until the director's reason field is non-empty. Never pre-filled.
  decision-30 makes the note required; a required field the assistant fills in is a required field
  that has been abolished.
- A proposal expires after 15 minutes. Executing a stale diff applies an edit the director never saw.
- One approval, one execution, one audit row. Re-generating never reuses an approval.

assistant_approvals: id, tenant_id, turn_id, capability, params_json, diff_json (frozen at proposal
time), proposed_at, expires_at, approved_by (NEVER null on an executed row), approved_at, reason,
executed_at, result_ref, outcome IN (approved, discarded, expired, failed).
Discards are rows too — a proposal the director REJECTED is the most interesting row in the table
and the only honest error-rate signal this feature will ever have.

Provenance with NO schema change to decision-30's tables: shift_edits.note carries
'Assistent-Vorschlag #<turn_id>, bestaetigt von <admin>: <reason>'. A director reading shift_edits
months later must not need to know a chat existed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V7: executing with approval_id null, or with an approval whose approved_by is null, returns 403. RED if it succeeds
- [ ] #2 V8: a proposal older than 15 minutes returns 409. RED when the clock is frozen forward and it still executes
- [ ] #3 V16: the money delta is in the submit button's accessible name; changed rows carry a visible marker, not only colour. RED when the delta is removed from the accessible name
- [ ] #4 No assistant-only mutating endpoint exists; a test asserts the execute path only calls registered /admin/* handlers
- [ ] #5 shift_edits.note carries the provenance string on every assistant-originated edit; decision-30's tables are unchanged
- [ ] #6 Discarded and expired proposals are written as rows
<!-- AC:END -->
