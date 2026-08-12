---
id: TASK-121
title: >-
  Phone identity migration: workers.phone_e164 UNIQUE, OTP challenges, spend
  counters in Postgres
status: To Do
assignee: []
created_date: '2026-08-12 06:13'
labels:
  - db
  - server
  - security
milestone: m-6
dependencies:
  - TASK-120
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
priority: high
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH sections 2 and 12, implementation steps 2 and 4.

MIGRATION NUMBER COLLISION - READ THIS FIRST. Three separate designs each wrote "migration 006":
this one (decision-31 phone identity), TASK-78 (zones, decision-33) and TASK-77 (tenancy,
decision-32). Only one can be 006. Allocation, by the order the plan ships them:
    006 = phone identity (this task)    007 = zones (TASK-78)    008 = tenancy (TASK-77)
Whoever runs second renumbers. NEVER run two of them in parallel against the same database.
migrate.js runs psql -1, so the file carries no BEGIN/COMMIT.

CONTENT: workers.phone_e164 UNIQUE (nullable, so the migration is additive and safe to apply to
production later); phone_confirmed_at; the OTP challenge table; the rate-limit and spend counters.

COUNTERS LIVE IN POSTGRES, NOT IN MEMORY. systemctl restart must not refill a spend limit. This is
the whole reason the counters are in the schema at all.

LOOKUP IS BY PHONE NUMBER, NOT BY DIGEST: the brute-force search space is then per-worker, not
shared across all workers. hashToken("<e164>:<code>").

apple_sub is KEPT as an audit column. It is not dropped by this migration.

BACKFILL: normalise existing numbers only. It NEVER sets phone_confirmed_at - a number typed by an
admin is not a confirmed number. Output reviewed by a human before it is applied anywhere.

MUST NOT REGRESS: production is READ-ONLY in this run. Rehearse against a restored dump in
nfc_demo, guarded by demo/check-guards.sh. Live data is 8 shifts / 4 workers / 1 location.

SEQUENTIAL with TASK-77 and TASK-78 - shared migration namespace and shared tables.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration is additive and all-NULLable; applied to a restored dump in nfc_demo it changes zero existing rows (row count + checksum identical before/after)
- [ ] #2 phone_e164 is UNIQUE; inserting a duplicate raises, proven by a check
- [ ] #3 The section 12 read-only pre-checks run against production and their output is pasted into the notes BEFORE any migration is considered
- [ ] #4 Spend and rate-limit counters survive a process restart - proven by restarting the service mid-window and asserting the counter did not reset
- [ ] #5 Backfill script normalises only; a check asserts it never writes phone_confirmed_at. Making it confirm -> RED
- [ ] #6 No BEGIN/COMMIT in the migration file
<!-- AC:END -->
