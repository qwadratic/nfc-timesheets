---
id: TASK-93
title: 'Capability registry, assistant_audit and the refusal path'
status: To Do
assignee: []
created_date: '2026-08-12 06:02'
labels:
  - assistant
  - security
dependencies:
  - TASK-92
references:
  - backlog/decisions/decision-36.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: high
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Still no model and no UI. This is the classifier decision-36 §1-2 requires.

server/lib/assistant/registry.js — one frozen, readable object. It IS the security policy.
Each entry: { tier: 'auto'|'approval', view|endpoint|doc|sql, params: <shape> }.
Tier D refusal list is a separate frozen Set and has NO approval path:
DELETE /admin/workers/:id, POST /admin/workers/:id/enrolment-code, POST /admin/portal-grants,
every DELETE /admin/*, POST /admin/settings, DELETE /admin/settings/:key.

An operation is a (capability_id, params) pair. Nothing else is an operation. Unknown id or
failing params => refusal row + a German 'das kann ich noch nicht' + a one-click 'als Wunsch
festhalten' that files a NOTE, never an executable. There is no runtime button that blesses an
unregistered operation (decision-36 §2C).

assistant_audit, append-only, EVERY turn including refusals and failures (design doc §5):
id, tenant_id, conversation_id, turn_id, created_at, admin_id, actor('admin'|'system'),
kind, question_text, capability, params_json, tier, sql_text, refusal_reason,
result_row_count, result_digest, model, prompt_tokens, completion_tokens, cost_millicents,
duration_ms, approval_id.

NEVER store result rows — result_digest is sha256(serialised result). A table of assistant
answers is a second copy of payroll data with weaker access control.
Retention split: 7 years when tied to a mutation (BAO §132, decision-30), 90 days for pure reads;
the sweep runs in the same nightly timer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 registry.js is a single frozen object; adding a capability is the only way to add an operation
- [ ] #2 Unregistered capability id AND registered-id-with-bad-params both produce a refusal row and ZERO database statements (V5)
- [ ] #3 V5 goes RED when the loop is given a default/fallthrough handler — RED output pasted into notes
- [ ] #4 assistant_audit is append-only (no UPDATE/DELETE grant to the app role on it beyond the retention sweep) and stores a digest, never rows
- [ ] #5 Refusal reasons are machine-readable codes, not prose
- [ ] #6 Tier-D list is a frozen Set with no code path that can bypass it; a test proves each entry refuses
<!-- AC:END -->
