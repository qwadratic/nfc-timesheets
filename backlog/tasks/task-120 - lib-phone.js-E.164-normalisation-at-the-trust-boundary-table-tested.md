---
id: TASK-120
title: 'lib/phone.js: E.164 normalisation at the trust boundary, table-tested'
status: To Do
assignee: []
created_date: '2026-08-12 06:12'
labels:
  - server
  - security
milestone: m-6
dependencies: []
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
priority: high
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH section 1, implementation step 1. Pure function, no schema, no live path, zero risk -
which is why it goes first.

Austrian input reality: 0664..., +43664..., 0043664..., with spaces, slashes and dashes. One
normaliser at the boundary, called by every entry point, so that two rows can never disagree about
whether they are the same person.

The section 1 table has already been EXECUTED, not asserted: 14/14 pass, and dropping the 00 rule
turns 0043... RED. Port that table verbatim into check-api.js.

JOB: JTBD #3 - invite a worker on the spot. Identity is the whole feature.

MUST NOT REGRESS: dependency budget. Server deps are pg + @sentry/node and nothing else
(decision-23). No libphonenumber, no new package. If that ever needs to change it needs a decision
record first.

PARALLEL: yes with everything. New file, no shared edits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 server/lib/phone.js exports a normaliser that returns E.164 or a typed rejection - never a silently mangled string
- [ ] #2 The section 1 table lands in check-api.js as a table-driven test, all 14 cases
- [ ] #3 Mutation proof: drop the 00 prefix rule -> the 0043 case goes RED. Paste the RED output
- [ ] #4 No new npm dependency added - server/package.json still lists exactly pg and @sentry/node
<!-- AC:END -->
