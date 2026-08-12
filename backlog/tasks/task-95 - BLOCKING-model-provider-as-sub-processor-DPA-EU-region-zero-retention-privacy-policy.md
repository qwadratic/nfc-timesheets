---
id: TASK-95
title: >-
  BLOCKING: model provider as sub-processor - DPA, EU region, zero retention,
  privacy policy
status: To Do
assignee: []
created_date: '2026-08-12 06:03'
labels:
  - assistant
  - privacy
  - blocked-on-owner
dependencies:
  - TASK-94
references:
  - backlog/decisions/decision-36.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: high
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This blocks ENABLING the assistant in production. It does not block building steps 1-3.

The model provider becomes a sub-processor of employee data. Under decision-32 §11 the tenant is
the controller and we are the processor (Art 28) — a sub-processor may not simply appear.

Required before ASSISTANT_ENABLED is ever set on the VM:
- EU-region endpoint, or Standard Contractual Clauses on file.
- Contractual ZERO RETENTION and NO TRAINING on submitted data, in writing. Pseudonymisation
  (TASK-94) reduces the harm; it does not remove the transfer.
- Provider named in the DPA and in the German privacy policy page TASK-43 must write anyway.

Split, same shape as TASK-43: an agent can draft the disclosure text and wire the env gate.
The OWNER signs the DPA and makes the legal declaration. An agent must not accept terms on
behalf of the account holder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider chosen and its region/retention/training terms recorded in the task notes with a link
- [ ] #2 German privacy policy names the sub-processor, the categories transferred, and the pseudonymisation
- [ ] #3 DPA/SCC status recorded; owner sign-off noted explicitly
- [ ] #4 ASSISTANT_ENABLED is documented as unset until all three are true, and the runbook says so
<!-- AC:END -->
