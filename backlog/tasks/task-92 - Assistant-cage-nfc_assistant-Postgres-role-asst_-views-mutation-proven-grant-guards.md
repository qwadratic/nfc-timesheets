---
id: TASK-92
title: >-
  Assistant cage: nfc_assistant Postgres role + asst_* views + mutation-proven
  grant guards
status: To Do
assignee: []
created_date: '2026-08-12 06:02'
labels:
  - assistant
  - security
  - db
dependencies: []
references:
  - backlog/decisions/decision-36.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: high
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The security model before anything that can be talked into anything. No model, no UI, no chat route in this task.

Create the read cage decision-36 §3 requires (design doc §3.4):

  CREATE ROLE nfc_assistant LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  ALTER ROLE nfc_assistant SET default_transaction_read_only = on;
  ALTER ROLE nfc_assistant SET statement_timeout = '3s';
  ALTER ROLE nfc_assistant SET idle_in_transaction_session_timeout = '5s';
  ALTER ROLE nfc_assistant SET search_path = 'public, pg_temp';
  REVOKE ALL ON SCHEMA public FROM nfc_assistant;
  GRANT USAGE ON SCHEMA public TO nfc_assistant;
  GRANT SELECT ON <the nine asst_* views> TO nfc_assistant;

Nine views: asst_shifts, asst_workers, asst_locations, asst_contracts, asst_material_requests,
asst_inventory, asst_payroll, asst_clients, asst_rate_history.

NEVER in any view (design doc §4.1): admins.password_hash, sessions.token, worker_sessions.token,
workers.apple_sub, workers.enrolment_code_hash, workers.phone_e164, workers.email, admins.email,
contacts.email, portal_grants.token_hash, secret-shaped app_settings rows.
Derived booleans instead: has_live_code := enrolment_code_expires_at IS NOT NULL,
can_receive_sms := phone_e164 IS NOT NULL.

Views carry NO tenant predicate (decision-32 lands as a zero-character change).
Migration runs as the OWNER, never as nfc_assistant. Additive/expand only.
Second DATABASE_URL_ASSISTANT in /etc/nfc/env, psst-vaulted, pool max 2 — never the app pool.
Runbook (backlog/docs/runbook-vm-provisioning.md) grows the role step.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration 00N creates the role, the nine views and the grants; runs as owner; is additive only
- [ ] #2 check-api.js asserts as nfc_assistant that DELETE FROM shifts, UPDATE shifts, and WITH d AS (DELETE FROM shifts RETURNING *) SELECT * FROM d all ERROR (V2)
- [ ] #3 check-api.js asserts as nfc_assistant that SELECT password_hash FROM admins, token FROM sessions, apple_sub/enrolment_code_hash/phone_e164 FROM workers, token_hash FROM portal_grants all ERROR (V3)
- [ ] #4 A check reads information_schema.columns for every asst_* view and asserts zero intersection with the denylist — asserted from the catalogue, NOT by reading the SQL text (V4)
- [ ] #5 A check asserts server/routes/admin.js registers no DELETE route on /admin/shifts (V1)
- [ ] #6 Every one of V1-V4 is shown going RED by its documented mutation, and the RED output is pasted into the task notes
- [ ] #7 Second pool is max:2 and cannot starve the app pool; no clock-in path imports it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Write the nine views against the live column list (read-only inspection of nfc, or nfc_demo). 2. Migration with role+grants. 3. Guards in check-api.js. 4. Run each mutation, capture RED. 5. Runbook step.
<!-- SECTION:PLAN:END -->
