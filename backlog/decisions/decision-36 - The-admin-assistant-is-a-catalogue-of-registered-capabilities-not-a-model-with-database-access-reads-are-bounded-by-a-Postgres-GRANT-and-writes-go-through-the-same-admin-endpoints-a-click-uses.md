---
id: decision-36
title: >-
  The admin assistant is a catalogue of registered capabilities not a model with
  database access - reads are bounded by a Postgres GRANT and writes go through
  the same admin endpoints a click uses
date: '2026-08-12 06:00'
status: proposed
---
## Context

The proposal is a chat surface inside the admin panel where an agent with database and API reach
helps with the work the panel has no screen for: reports, e-mail drafts, an insight of the day,
troubleshooting a live instance. The motivation is sound — building a screen per unbuilt feature
is how an operations tool turns into a CRM — and the reach is exactly what makes it useful.

It is also the most dangerous idea on the board. This database holds Austrian payroll data about
identified employees: `workers.hourly_rate_cents`, every shift they worked, their building
addresses, their phone numbers, and the hashes and tokens that *are* their credentials
(`admins.password_hash`, `sessions.token`, `worker_sessions.token`, `workers.apple_sub`,
`workers.enrolment_code_hash`, `portal_grants.token_hash`). A read leak here is a GDPR incident;
a bad write lands on a payslip and gets argued about with a person.

The obvious architecture — hand the model a connection, let it emit SQL, classify the SQL before
running it — **cannot be built safely, and the reason is not diligence.** Deciding whether an
arbitrary SQL string is read-only and touches no forbidden column is a semantics problem, and
Postgres supplies the counter-examples: `WITH d AS (DELETE FROM shifts RETURNING *) SELECT * FROM d`
is a statement beginning `WITH` that deletes payroll history; `DO` blocks, side-effecting
functions, `COPY … TO PROGRAM`, comments and unicode homoglyphs each defeat a regex. Any string
classifier is a list that goes stale, guarding a table that cannot be restored from a mistake.

This is the same failure shape decision-32 identified for tenancy: *the predicate that gets
forgotten is the predicate that is never written*. There, isolation moved out of ~110 hand-written
SQL clauses into one RLS policy. The same move is available here.

Design, threat model, capability catalogue, cost model and the sixteen mutation checks:
`backlog/docs/ADMIN-ASSISTANT.md`.

## Decision

**Build the assistant as a registry of hand-written capabilities. The model's only power is to
name one and fill its parameters. Reads are bounded by a Postgres `GRANT`; writes have no path of
their own.**

1. **Classification is by capability identity, not by inspecting a generated string.**
   An operation is a `(capability_id, params)` pair looked up in a frozen table in
   `server/lib/assistant/registry.js`. "Is this SQL safe" is undecidable; "is this id in the
   registry" is a hash lookup. That file is the entire security policy and is readable in one sitting.

2. **Two runtime tiers, and a third that is not a runtime tier at all.**
   - **A `auto`** — registered, read-only, parameterised. Executes immediately, logged.
   - **B `approval`** — registered, mutating. Produces a *proposal*; nothing runs until the
     director clicks, and the click calls an ordinary `/admin/*` endpoint.
   - **C unknown** — not in the registry, or params fail validation. **Refused.** The brief's
     "explicit developer approval" is honoured as *a pull request, a review gate and a deploy* —
     never a runtime button. A button that lets a human bless an arbitrary model-generated
     operation is a code path that executes arbitrary intent, whose safety rests on a tired
     person reading SQL at 18:00 on a Friday.
   - **D refused outright, no approval path, regardless of who asks** — `DELETE /admin/workers/:id`
     (it destroys that worker's sessions: an assistant that can log a cleaner out at 06:00 is a
     denial of service on clock-in), `POST /admin/workers/:id/enrolment-code` and
     `POST /admin/portal-grants` (credentials that exist in exactly one HTTP response),
     every `DELETE /admin/*`, and `POST|DELETE /admin/settings` — **nothing may raise its own budget.**

3. **The denylist is a `GRANT`, not a regex.** A dedicated role `nfc_assistant`
   (LOGIN, NOSUPERUSER, NOBYPASSRLS, not the table owner) holds `SELECT` on nine `asst_*` views and
   on nothing else — no base tables, no functions, no sequences — with
   `default_transaction_read_only = on`, `statement_timeout = 3s`,
   `idle_in_transaction_session_timeout = 5s` and a pool of `max: 2`. The forbidden columns are not
   "un-asked-for", they are `ERROR: permission denied`, including inside a CTE, forever, for code
   nobody has written yet. `NOBYPASSRLS` means decision-32 landing is a no-op here.

4. **The assistant has no write path.** There is no assistant-only mutating endpoint and no write
   grant. Every approved tier-B execution is an ordinary authenticated call to an existing
   `/admin/*` handler, so *the blast radius of an approved assistant write is exactly the blast
   radius of a director's click, and not one byte more* — same validators, same 4xx, same audit rows.

5. **Deleting shift history stays impossible for two independent reasons**, neither a policy:
   `server/routes/admin.js` registers 29 routes, nine of them `DELETE`, and none is on `shifts`
   (verified 2026-08-12); and the assistant's role cannot write at all. Both are mutation-checked.

6. **The model never computes a number; it phrases a number SQL computed.** Every generated string
   passes a numeral-set verifier — every numeral in the sentence must have been handed to it, and
   none handed to it may be missing — and failure falls back silently to a deterministic template.
   Every assistant-produced figure carries a "Nachrechnen" link to the absolute-range URL
   (`from`/`to`, never `period`) that produced it. **An insight you cannot click through to the
   rows is a rumour.**

7. **The prompt is an egress channel and is treated as one.** Everything outbound passes
   `lib/assistant/egress.js`: `scrub.js`'s existing `SECRET_KEY_RE` reused verbatim, plus
   per-conversation pseudonymisation (`MA-1`, `OBJ-1`, `KD-1`) re-substituted on return, plus row
   and byte caps. The model provider is a **sub-processor** of employee data under Art 28 —
   EU region or SCCs, contractual zero-retention and no-training, named in the DPA and the privacy
   policy. `ASSISTANT_ENABLED` stays unset until all three are true.

8. **Everything is audited, including refusals.** `assistant_audit` records who asked, what ran,
   the tier, the exact SQL for `freeform_read`, and a **sha256 digest of the result — never the
   rows**, because a table of assistant answers is a second copy of payroll data with weaker
   access control. `assistant_approvals` records the frozen diff, `approved_by` (never null on an
   executed row), the 15-minute expiry, and `discarded` / `expired` outcomes. Retention splits:
   7 years when tied to a mutation (BAO §132, per decision-30), 90 days for pure reads.

9. **Provenance reuses decision-30's tables with no schema change to them.** The required
   `shift_edits.note` carries `"Assistent-Vorschlag #<turn_id>, bestätigt von <admin>: <reason>"`.
   The director's reason field stays mandatory and is never pre-filled — a required field the
   assistant fills in is a required field that has been abolished.

10. **gbrain states facts about the SYSTEM, never facts about the DATA.** A knowledge base
    containing a figure is a second source of truth by construction. Corpus lives in the repo with
    `describes` + `describes_sha256` frontmatter checked by `check-gbrain.mjs` (the shape of
    `ops/check-branding.mjs`, decision-24); director notes live append-only in `gbrain_notes`.
    Retrieval is a ~2 KB index plus a `gbrain_read` capability — **no vector database**; the upgrade
    path is Postgres `tsvector`, and `pgvector` would be a decision record, not a shrug.

11. **Zero model calls on page load, ever.** The dashboard reads one cached `assistant_insight` row
    produced by a nightly `nfc-assistant-insight.timer` at 04:15 Vienna (the shape of
    `nfc-autoclose.timer`, decision-18). On-demand turns are capped at 4 tool calls, 30 s wall
    clock, a token cap, and a per-tenant daily spend cap in `app_settings`.

12. **Restating decision-23 with a second subject: the assistant must never be required to boot and
    must never block a clock-in.** `ASSISTANT_ENABLED` absent → `/admin/assistant/*` is a 404 and
    the process is otherwise identical. `routes/app.js` shares no module with `lib/assistant/`.

13. **Zero new dependencies.** The model is reached with global `fetch` (Node ≥ 22). No LLM SDK, no
    vector store, no SMTP client, no queue. decision-23's budget — `pg` + `@sentry/node` — holds
    unchanged. That the assistant cannot send e-mail is a *feature*: a human reads every drafted
    word before it leaves.

## Consequences

- **Capability coverage becomes the product's growth edge.** Every new question the director wants
  answered generically is a pull request, not a prompt tweak. That is slower and it is the price of
  point 1; `freeform_read` (§3.4 of the design doc) exists precisely to keep that price bounded.
- **A second Postgres role and nine views enter the schema**, so provisioning
  (`backlog/docs/runbook-vm-provisioning.md`) grows a step and `check-api.js` grows the V2–V4
  guards. Migrations must be run as the owner, not as `nfc_assistant`.
- **The DPA / sub-processor work blocks production enablement**, not development. Steps 1–3 of the
  design doc's order of work can ship with `ASSISTANT_ENABLED` unset and nothing risked.
- **The audit tables are a new place payroll-adjacent data could leak**, which is why they hold a
  digest and not rows, and why `sql_text` is not shown to non-developers in the panel.
- **`material_requests.note` is a future prompt-injection surface** the moment workers can type
  free text into it, because that text would enter the assistant's context. No `asst_*` view
  exposes worker-authored free text today; that constraint is now load-bearing and is checked.
- **Interaction with decision-32:** the assistant role is `NOBYPASSRLS` and not the table owner from
  day one, so multi-tenancy lands without revisiting this record. Until it lands, the single-tenant
  assumption holds and the views carry no tenant predicate — deliberately, so that adding one is
  the same zero-character change decision-32 promises everywhere else.
- **This decision does not authorise a chat that can be talked into anything.** If the tier-D list,
  the `GRANT`, or the "no write path of its own" property is ever relaxed, that is a new decision
  record superseding this one — not a patch.
