# The admin assistant — design, plan and security model

Date: 2026-08-12 · Scope: a chat surface inside the admin panel with database and API reach.
**Spec only. No code changed, no route added, nothing deployed. Production untouched.**

Companion to `backlog/docs/IA-AND-JTBD.md` (what the panel is *for*) and
`backlog/docs/UX-AUDIT.md` (what is broken). The jobs ranked there are the jobs this assistant
serves; it adds no thirteenth job.

Binding constraints, restated because every proposal below obeys them:

- **decision-16 / decision-23** — server dependencies are `pg` + `@sentry/node` and nothing else.
  No LLM SDK, no vector database, no SMTP client, no queue. The model is reached with global
  `fetch`. If a design needs an npm package it is the wrong design.
- **decision-16** — `output: 'export'`; the panel is static. The chat is a client component
  talking to one new `/admin/*` endpoint. No server component, no dynamic route.
- **decision-29** — it works at 390px.
- **decision-8 / 17** — German default, `de.json`/`en.json` exact key parity, no bare literals.
- **decision-30** — money-affecting edits write `shift_edits` / `worker_rate_changes`, with a
  required note. The assistant does not get an exemption.
- **decision-32 (proposed)** — tenancy comes from the session row and is enforced by Postgres,
  not by application predicates. Everything below is built so that record landing is a no-op.
- Money integer cents, time integer minutes, Vienna wall clock, periods half-open `[from, to)`.

---

## 0 · The one-paragraph version

The assistant is **not a model with database access**. It is a **catalogue of hand-written,
registered capabilities**; the model's only power is to name one and fill its parameters. Reads
are bounded by a Postgres `GRANT` to a dedicated read-only role, so the forbidden columns are
unreachable rather than un-asked-for. Writes have no path of their own — a tier-B capability
produces a *proposal*, and executing it calls the same `/admin/*` handler a director's click
calls, with the same validation and the same audit rows. Deleting shift history is impossible for
two independent reasons: no such endpoint exists, and the assistant's database role cannot write
at all. Every turn is logged. Nothing runs on page load.

---

## 1 · Why the obvious design is the dangerous one

The obvious design is: give the model a database connection, let it write SQL, and classify the
SQL it produces as safe or unsafe before running it.

**That classifier cannot be written.** Deciding whether an arbitrary SQL string is read-only and
touches no forbidden column is a semantics problem, and the attack surface is every feature
Postgres has: CTEs (`WITH x AS (DELETE … RETURNING *) SELECT …` is a `SELECT` statement that
deletes), `DO` blocks, functions with side effects, `COPY … TO PROGRAM`, comments and unicode
homoglyphs breaking any regex, `pg_read_file`, and set-returning functions in the target list.
Every one of those defeats a string check, and the string check is the only thing standing between
a plausible-sounding sentence and the payroll table.

So the design inverts it. **Classification is by the identity of a pre-registered capability, not
by inspection of a generated string.** „Is this string safe" is undecidable; „is `payroll_summary`
in the registry, and is `tier` `auto`" is a hash lookup. And the residual risk of the one
capability that *does* take model-written SQL is removed by the database, not by a reader: the
role it runs as has been granted `SELECT` on nine views and nothing else, in a read-only
transaction, with a 3-second statement timeout.

This is deliberately the same argument shape as decision-32: *the predicate that gets forgotten is
the predicate that is never written*. There, isolation moved out of ~110 hand-written SQL clauses
into one RLS policy. Here, the denylist moves out of a regex nobody will maintain into a `GRANT`
Postgres enforces on every statement forever.

---

## 2 · Architecture

```
  panel (static export)                 Node process (one, decision-16)
  ┌────────────────────┐   POST         ┌──────────────────────────────────────┐
  │ AssistantDrawer    │──/admin/─────► │ routes/assistant.js   auth:"admin"   │
  │  · question box    │  assistant/    │   └─ lib/assistant/loop.js           │
  │  · turn list       │  turns         │        ├─ registry.js  (capabilities)│
  │  · proposal cards  │ ◄──────────────│        ├─ egress.js    (scrub+alias) │
  │  · „Nachrechnen"   │   turn JSON    │        ├─ audit.js     (append-only) │
  └────────────────────┘                │        └─ budget.js    (caps, kill)  │
           │ approve                    └───────┬──────────────┬───────────────┘
           ▼                                    │              │
  POST /admin/shifts, PATCH /admin/…    ┌───────▼──────┐  ┌────▼─────────────┐
  (the SAME handlers a click calls)     │ pool nfc_app │  │ pool nfc_asst    │
                                        │ writes, RLS  │  │ SELECT on 9 views│
                                        └──────────────┘  │ read-only, 3 s   │
                                                          └──────────────────┘
                                             fetch ──► model provider (EU, no-retention)
```

Four properties of that picture are load-bearing:

1. **Two pools, two roles.** The assistant's read pool is a different Postgres role from the
   application's. `max: 2` — the assistant can never starve a clock-in of connections.
2. **The approve arrow leaves the browser.** The director's approval is a normal authenticated
   request to a normal admin endpoint. The assistant process never holds write authority.
3. **The model is downstream of `egress.js`, never upstream of the database.** Nothing the model
   returns reaches SQL except as a validated parameter to a named capability.
4. **`ASSISTANT_ENABLED` absent → the whole box is inert**, exactly as decision-23 requires of
   Sentry. Restated for this feature and equally binding: **the assistant must never be required
   to boot, and must never sit on the path of a clock-in.** `routes/app.js` shares no module with
   `lib/assistant/`.

`ponytail:` one turn is one request/response — no streaming, no websocket, no job queue. Ceiling:
a 6-second answer shows a spinner for 6 seconds. Upgrade path: `text/event-stream` on `node:http`,
which is still zero dependencies, once someone actually complains.

---

## 3 · The two-tier permission model

### 3.1 How an operation is classified

An operation is a `(capability_id, params)` pair. Nothing else is an operation. The model emits
JSON; `registry.js` looks the id up in a frozen, code-defined table:

```js
// server/lib/assistant/registry.js  — the entire security policy, in one readable file.
export const CAPABILITIES = Object.freeze({
  payroll_summary:  { tier: "auto",     view: "asst_payroll",   params: { from: "iso", to: "iso" } },
  open_shifts:      { tier: "auto",     view: "asst_shifts",    params: {} },
  gbrain_read:      { tier: "auto",     doc:  true,             params: { id: "slug" } },
  freeform_read:    { tier: "auto",     sql:  "model",          params: { sql: "text" } },   // §3.4
  propose_shift_fix:{ tier: "approval", endpoint: "PATCH /admin/shifts/:id",
                      params: { id: "int", start: "iso", end: "iso", note: "text" } },
  propose_rate:     { tier: "approval", endpoint: "POST /admin/workers",
                      params: { id: "int", cents: "int", kind: "raise|correction", reason: "text" } },
  // …
});
```

| tier | meaning | who approves | when |
|---|---|---|---|
| **A — `auto`** | registered, read-only, parameterised, projection-bounded | nobody, at run time | executes immediately |
| **B — `approval`** | registered, mutating | **the director**, in the panel, per proposal | after an explicit click |
| **C — unknown** | not in the registry, or params fail validation | **a developer, in a pull request** | after a deploy |
| **D — refused** | on the refusal list below | **nobody, ever** | never |

**Tier C is not a runtime approval path, and that is the point.** The brief asks that unknown
operations need explicit developer approval before they run — and the honest implementation of
„developer approval" is *a commit, a review gate and a deploy*, not a button. A button that lets a
human bless an arbitrary model-generated operation is a code path that executes arbitrary intent
whose safety rests on a tired person reading SQL at 18:00 on a Friday. There is no such button.
An unknown request answers, in German, „das kann ich noch nicht" plus a one-click „als Wunsch
festhalten" that files a note — and files it as a *note*, not as an executable.

Adding a capability therefore passes the same gates as any other change: Biome, `check-api.js`,
the review gate in `AGENTS.md`, and this document's §7 checks.

### 3.2 What a tier-B proposal looks like on screen

A proposal is never prose. It is a rendered before/after over the exact fields that will change,
plus the endpoint that will be called:

```
  Vorschlag · Schicht 214 korrigieren                        [ Verwerfen ] [ Ausführen ]

    Mitarbeiter   Anna K.            (unverändert)
    Objekt        Stiftgasse 3       (unverändert)
    Beginn        06:00  →  06:00    (unverändert)
    Ende          14:00  →  11:45    ▲ geändert
    Dauer         8 h 00 →  5 h 45   ▲ −2 h 15
    Lohnwirkung   116,00 € → 83,38 € ▲ −32,62 €          ← computed in SQL, not by the model
    Grund         (Pflichtfeld, decision-30) …

    Wird ausgeführt als:  PATCH /admin/shifts/214
```

Rules the card must obey:

- **Every figure in the card is computed server-side from the rows**, using the same resolver
  payroll uses (decision-30 §1). The model supplies the *intent* (`end = 11:45`); it never
  supplies a euro amount. A money figure the model typed is not shown anywhere in this product.
- **„Ausführen" is disabled until the reason field is non-empty**, because decision-30 makes the
  note required and a required field that the assistant pre-fills with „vom Assistenten
  vorgeschlagen" is a required field that has been abolished.
- A proposal **expires after 15 minutes**. The underlying rows can change; executing a stale diff
  is how the panel would apply an edit the director never saw.
- Re-generating a proposal never reuses the previous approval. One approval, one execution, one
  audit row.
- Accessibility: the card is a `<form>` with a `<fieldset><legend>`, the changed rows carry a
  visible „geändert" marker and not only a colour, and the money delta is in the accessible name
  of the submit button („Ausführen — Lohnwirkung minus 32,62 €"). **A screen reader user must not
  be able to approve a money change whose size was communicated only in red.**

### 3.3 The approval record

`assistant_approvals`, append-only, written in the same transaction as the execution:

| column | why |
|---|---|
| `id`, `tenant_id` | |
| `turn_id` | joins to `assistant_audit` — who asked, and in which conversation |
| `capability`, `params_json` | exactly what was proposed |
| `diff_json` | the rendered before/after, frozen at proposal time |
| `proposed_at`, `expires_at` | the 15-minute window |
| `approved_by` (`admins.id`), `approved_at` | **who**. Never nullable on an executed row. |
| `reason` | the director's own words, mirrored into `shift_edits.note` |
| `executed_at`, `result_ref` | the `shift_edits.id` / `worker_rate_changes.id` produced |
| `outcome` | `approved` · `discarded` · `expired` · `failed` |

Discards and expiries are rows too. **A proposal the director rejected is the most interesting
row in the table** — it is the record of the assistant being wrong, and it is the only data that
can ever tell you the assistant's error rate.

Provenance lands in decision-30's existing tables with **no schema change to them**: the required
`shift_edits.note` carries
`„Assistent-Vorschlag #<turn_id>, bestätigt von <admin>: <reason>"`. The audit trail decision-30
already demands is the audit trail for this feature too, which is exactly right — a director
reading `shift_edits` months later must not need to know that a chat existed.

### 3.4 The one capability that takes model-written SQL

`freeform_read` exists because „wie viele Schichten begannen im Juli nach 9 Uhr in der Stiftgasse"
is a real question and pre-registering every aggregation is a losing game. It is tier A, and it is
safe for reasons that have nothing to do with reading the SQL:

```sql
CREATE ROLE nfc_assistant LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
ALTER ROLE nfc_assistant SET default_transaction_read_only = on;
ALTER ROLE nfc_assistant SET statement_timeout = '3s';
ALTER ROLE nfc_assistant SET idle_in_transaction_session_timeout = '5s';
ALTER ROLE nfc_assistant SET search_path = 'public, pg_temp';
REVOKE ALL ON SCHEMA public FROM nfc_assistant;
GRANT USAGE ON SCHEMA public TO nfc_assistant;
GRANT SELECT ON asst_shifts, asst_workers, asst_locations, asst_contracts,
                asst_material_requests, asst_inventory, asst_payroll,
                asst_clients, asst_rate_history TO nfc_assistant;
-- and nothing else. No base tables. No functions. No sequences.
```

Consequences, each of which replaces a check somebody would otherwise have had to write:

- `default_transaction_read_only` → `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/DDL error at the server,
  including inside a CTE. **The `WITH … DELETE … RETURNING` trick fails.**
- No grant on base tables → `admins.password_hash` is not merely unrequested, it is
  `ERROR: permission denied for table admins`. The nine views do not select the forbidden columns
  (§4.1), so there is no route to them at all.
- `statement_timeout = 3s` → a cartesian join is an error message, not an outage. `max: 2`
  connections → it is an error message on a pool that cannot touch the app's.
- `NOBYPASSRLS` + not the table owner → when decision-32 lands, the assistant is tenant-scoped by
  the same policies as everything else, with no code change here.
- `COPY … TO PROGRAM` requires `pg_write_server_files`/superuser → refused.

`ponytail:` no SQL parsing, no allowlist regex, no `EXPLAIN` pre-flight. The database is the
parser and it is better at it than we are. Ceiling: the model can still write a *wrong* query and
get a confidently wrong number — which is §6's problem, not this section's, and is why every
assistant-produced figure carries a „Nachrechnen" link. Upgrade path if freeform reads prove more
trouble than they are worth: flip `freeform_read` to `tier: "approval"` — one word in the registry
— or delete the entry, and the rest of the assistant is unaffected.

---

## 4 · Blast radius

### 4.1 What it may never read

Not „must not", **cannot**: none of these appear in any `asst_*` view, and the views are the only
objects granted.

| never readable | table.column | why |
|---|---|---|
| admin password hashes | `admins.password_hash` | a live credential; PHC string, offline-crackable |
| admin session tokens | `sessions.token` | a session hijack in a log line |
| worker session tokens | `worker_sessions.token` | ditto, per worker |
| Apple subject | `workers.apple_sub` | stable per-person identifier, PII in its own right (decision-22) |
| enrolment code hashes | `workers.enrolment_code_hash` | a live bearer credential (decision-26) |
| portal tokens | `portal_grants.token_hash` | the token **is** the client's credential |
| phone numbers | `workers.phone_e164` | PII **and** the second factor (decision-31) |
| e-mail addresses | `workers.email`, `admins.email`, `contacts.email` | PII; `contacts.email` is exposed **only** inside the e-mail-draft capability, §6.3 |
| the `app_settings` rows holding keys | `app_settings` where `key` matches a secret pattern | configuration is not knowledge |

Two derived facts are exposed instead of the raw column, deliberately, because the *question* is
legitimate and the *value* is not:

```
workers.enrolment_code_expires_at IS NOT NULL  →  asst_workers.has_live_code   (boolean)
workers.phone_e164 IS NOT NULL                 →  asst_workers.can_receive_sms (boolean)
```

The same list is already the denylist in `server/lib/scrub.js`, written for the telemetry
boundary. **It is reused verbatim, not re-typed** — that file's own header argues why two copies
would be two chances to get it wrong, and this is the second boundary it was waiting for.

### 4.2 What it may never write

**The assistant has no write path at all.** There is no `nfc_assistant` grant that permits a write
and no assistant-only mutating endpoint. Every tier-B execution is an ordinary authenticated call
to an existing `/admin/*` handler, so:

> the blast radius of an approved assistant write is **exactly** the blast radius of a director's
> click, and not one byte more.

That single sentence replaces a policy document. It also means every validator in
`server/lib/validate.js`, every 404, every `fail(400, …)` and every audit row applies unchanged.

On top of that, three endpoints are on a **refusal list — tier D, never proposable, no approval
path, regardless of who asks**:

| refused | endpoint | why |
|---|---|---|
| destroying a worker | `DELETE /admin/workers/:id` | it is a soft delete (`active=false`) *and* it destroys that worker's sessions — an assistant that can log a cleaner out of their phone at 06:00 is a denial-of-service on clock-in. JTBD-10's leaver flow stays a human decision. |
| minting an enrolment code | `POST /admin/workers/:id/enrolment-code` | the plaintext is returned once and never again. A credential that only exists in one HTTP response must not be minted by anything that can be talked into it. |
| minting a portal grant | `POST /admin/portal-grants` | the token is a client's read access to a building's history. Same reasoning. |
| deleting anything | every `DELETE /admin/*` | see below |
| changing configuration | `POST /admin/settings`, `DELETE /admin/settings/:key` | that is where `assistant.daily_cap_millicents` lives. Nothing may raise its own budget. |

### 4.3 Deleting shift history stays impossible

Two independent reasons, neither of which is a policy:

1. **There is no endpoint.** `server/routes/admin.js` registers 29 routes; the `DELETE` verbs are
   `workers/:id`, `workers/:id/enrolment-code`, `locations/:id`, `clients/:id`, `contacts/:id`,
   `inventory/:id`, `portal-grants/:token_hash`, `contracts/:id`, `settings/:key`.
   **`shifts` is not among them and never has been.** The assistant cannot call what does not
   exist, and it cannot add a route.
2. **The database refuses.** `default_transaction_read_only` on `nfc_assistant`, and no `DELETE`
   grant on any object.

Both are checked, both by mutation (§7 V1, V2). If someone adds `DELETE /admin/shifts/:id` in a
year, a test goes red and names this document.

### 4.4 The channel everybody forgets: the prompt is egress

Every row the assistant reads and puts in context **leaves the VM** and reaches the model
provider. That is a disclosure of employees' pay data to a third party, and no amount of tier-A
read-only-ness touches it.

`server/lib/assistant/egress.js`, the single funnel every outbound payload passes through:

1. **`scrubEvent`-grade key filtering**, reusing `scrub.js`'s `SECRET_KEY_RE`. Belt and braces: the
   views should not contain these keys, and if one ever does, it still does not leave.
2. **Pseudonymisation of identifiers.** Per conversation, a `Map` assigns stable aliases:
   `workers.name → MA-1, MA-2 …`, `locations.name / address → OBJ-1 …`,
   `clients.name → KD-1 …`. The provider sees „MA-2 hat im Juli 143 Stunden in OBJ-1 gearbeitet",
   never „Anna Kowalski … Stiftgasse 3". Aliases are substituted back on the way in for display.
   `ponytail:` a `Map` plus two `replaceAll` passes over the JSON before `JSON.stringify`.
   Ceiling: a name the *director typed by hand* into the question is not aliased, because only
   DB-sourced values are known to be names. Upgrade path: match the alias table against the
   question text on word boundaries before sending, at the cost of mangling the odd common noun.
3. **Row caps.** Max 200 rows and 32 KB per capability result into context. Over the cap, the
   assistant is told the count and the truncation and must say so in its answer — never silently
   reason over the first 200 of 4,000.
4. **A named exception, stated rather than hidden.** The e-mail-draft capability (§6.3) needs the
   real recipient name and building. It un-aliases exactly those two fields, and the UI says so
   before generation: „Dieser Entwurf enthält Klarnamen und wird an den Modellanbieter
   übertragen." Wage figures are never un-aliased, in any capability.

**Data protection, because this is the part that blocks production, not the code.** The model
provider becomes a **sub-processor** of employee data. Under decision-32 §11 the tenant is the
controller and we are the processor (Art 28), so a sub-processor may not simply appear:

- EU-region endpoint, or Standard Contractual Clauses on file.
- Contractual **zero retention and no training** on submitted data. Without that in writing, the
  feature does not ship — pseudonymisation reduces the harm, it does not remove the transfer.
- The provider is named in the privacy policy page that TASK-43 must write anyway, and in the DPA.
- `ASSISTANT_ENABLED` stays unset until all three are true. This is a **hard prerequisite task**,
  not a footnote.

---

## 5 · Audit

One append-only table, `assistant_audit`, written for **every** turn — answered, refused, failed
or over budget. No exceptions and no sampling.

| column | notes |
|---|---|
| `id`, `tenant_id`, `conversation_id`, `turn_id` | |
| `created_at` | `timestamptz`, Vienna rendered at display time only |
| `admin_id` | **who asked.** Never nullable except on the nightly job, which uses `NULL` + `actor='system'` |
| `actor` | `admin` · `system` |
| `kind` | `question` · `tool_auto` · `tool_proposed` · `tool_approved` · `tool_refused` · `answer` · `error` |
| `question_text` | the director's own words. Needed to reconstruct „what did you ask it" |
| `capability`, `params_json`, `tier` | **what ran** |
| `sql_text` | for `freeform_read` only: the exact statement, as sent |
| `refusal_reason` | tier-C/D refusals carry a machine-readable code, not prose |
| `result_row_count`, `result_digest` | `sha256` of the serialised result — **never the rows** |
| `model`, `prompt_tokens`, `completion_tokens`, `cost_millicents` | |
| `duration_ms` | |
| `approval_id` | joins `assistant_approvals` when a mutation happened |

Two rules that are easy to get wrong:

- **Never store result rows.** A table of assistant answers is a second copy of payroll data with
  weaker access control and no retention policy. The digest proves *which* answer was given
  (re-run the capability, hash, compare) without holding the data twice.
- **Retention is split**, because the two kinds have different obligations: turns tied to an
  executed mutation keep **7 years** (BAO §132, per decision-30); pure read turns keep **90 days**
  and are then deleted by the same nightly timer. A read log kept forever is a surveillance record
  of a director's thinking, and nobody asked for one.

The audit is *readable in the panel*, at `/settings/?tab=assistant` — a director who cannot see
what the assistant did cannot supervise it. The log view shows the question, the capability, the
row count and the outcome. It does not show `sql_text` to a non-developer, because SQL in front of
someone who cannot read it manufactures false confidence.

---

## 6 · gbrain — the knowledge base

### 6.1 The one rule

> **gbrain may state facts about the SYSTEM. It may never state facts about the DATA.**

„Eine `auto_closed`-Schicht ist ungeklärt, bis der Mitarbeiter sie bestätigt hat" is a system fact
and belongs in gbrain. „Wir haben vier Mitarbeiter" is a data fact and belongs in the database,
where it is true by construction. **A knowledge base containing a figure is a second source of
truth by construction**, and the drift is not hypothetical: within a month it will say four while
the database says nine, and the assistant will have to pick one.

### 6.2 What it stores and where

Two stores, because they have two different lifecycles and two different approvers:

| store | location | contents | approver | changes via |
|---|---|---|---|---|
| **corpus** | `server/assistant/gbrain/*.md`, in the repo, deployed with the code | the schema in prose, the capability catalogue, the German label glossary, the URL param contract (§5 of the IA doc), the accepted decisions in one-paragraph form, the empty-state rules | a developer | a pull request |
| **notes** | `gbrain_notes` table | the director's own operating procedures: „bei `auto_closed` erst anrufen, dann korrigieren"; „Objekt X wird nur Di/Do gereinigt" | the director | the panel, tier B |

Notes are versioned, never updated in place (`gbrain_notes` is append-only with a `supersedes_id`),
so „why did it tell me that in March" is answerable.

### 6.3 How it stays current

- **Digest pinning, the same shape as `ops/check-branding.mjs` (decision-24).** Each corpus file
  carries frontmatter naming the source it describes and that source's hash:

  ```yaml
  ---
  id: capability-catalogue
  describes: server/lib/assistant/registry.js
  describes_sha256: 9f2c…
  ---
  ```

  `node server/assistant/check-gbrain.mjs` recomputes the hash and **fails the build** when the
  source moved and the document did not. Stale documentation stops being a matter of diligence and
  becomes a red check.
- **A lint that enforces §6.1.** The same script refuses a corpus file containing a bare number
  ≥ 2 digits, a currency symbol, or a `€`/`EUR` amount outside a fenced code block. Mutation test:
  add „wir haben 4 Mitarbeiter" → RED.
- **Notes carry a review date.** A note unconfirmed for 180 days is shown to the assistant with
  „(ungeprüft seit …)" attached and is surfaced to the director for confirmation. It is not
  silently deleted — a stale note is still evidence of intent.

### 6.4 Retrieval, without a vector database

The corpus is ~20 documents of 1–3 KB. `ponytail:` send the **index** (id + one-line summary,
~2 KB total) with every turn, and let the model fetch a document by id through the tier-A
`gbrain_read` capability. No embeddings, no chunking, no similarity search, **no dependency**.

Ceiling: this breaks somewhere past ~100 documents or ~50 KB of index. Upgrade path, in order:
Postgres `tsvector` full-text search (already have Postgres; still zero dependencies), and only if
*that* demonstrably fails, `pgvector` — which is a decision record, not a shrug.

---

## 7 · The delightful surface, and how a wrong answer is caught

The governing rule for everything in this section:

> **The model never computes a number. It phrases a number that SQL computed.**

An assistant confidently wrong about money is worse than no assistant, and the only structural
defence is to keep arithmetic out of the model entirely. Everything below is „SQL computes,
model writes the German around it", plus a verifier that rejects the sentence when the numbers do
not match.

### 7.1 The numeral-set verifier

One function, used by every generated string in this section:

```js
// Every numeral that appears in the model's sentence must have been handed to it,
// and no numeral it was handed may have gone missing.
const numerals = (s) => new Set(s.match(/\d[\d.,]*/g)?.map(n => n.replace(/[.,]$/, "")) ?? []);
// verify(rendered, facts) -> true | false ; false => fall back to the deterministic template.
```

Failure is not an error message to the director; it is a **silent fall back to a deterministic
template sentence**, plus a Sentry event for us. A card that says „Assistent-Fehler" is worse than
a card that says the plain fact plainly.

Mutation test (§8 V6): stub the model to return the same sentence with one digit changed → the
card must render the template, and the test asserting „the model's sentence survived" goes RED.

### 7.2 Insight of the day

**Generated nightly**, never on page load. `nfc-assistant-insight.timer` at 04:15 Vienna — after
the 04:00 `pg_dump`, and modelled on the existing `nfc-autoclose.timer` (decision-18), so there is
no new supervision mechanism.

1. Run ~6 fixed, hand-written aggregate queries (hours by building this week vs. the trailing
   8-week mean; unresolved `auto_closed` count; material requests open > 3 days; buildings with no
   contract price; workers with shifts last month and none this month; the largest week-on-week
   move).
2. Pick the largest standardised deviation. **This choice is deterministic** — the model does not
   choose what is interesting, because „interesting" applied to payroll is where an assistant
   invents a story.
3. Hand the model the chosen fact as structured values and ask for **one German sentence**.
4. Verify with §7.1. Store one row in `assistant_insight` per tenant per day.

Rendering on `/`: one card, and **every card carries a „Nachrechnen" link** to the absolute-range
URL that produced it (`from`/`to`, never `period` — IA doc §3.1). **An insight you cannot click
through to the rows is a rumour.** Suppressed entirely when the underlying set is empty, per the
IA doc's empty-state rule 1 — no all-clear over an empty set.

Latency added to `/`: one indexed `SELECT` of one row. **Zero model calls on page load, ever.**

### 7.3 Banners

The weakest item here, and it is designed narrow on purpose. A banner type is chosen
deterministically from a fixed list (`all-clear`, `streak`, `month-end-due`, `nothing`); the model
writes only the wording. Constraints:

- **Never on `/payroll/` or `/reports/`.** A cheerful sentence next to a disputed number changes
  how the number is read.
- Only *checkable* claims. „Diese Woche wurde jede Schicht bestätigt" is a claim with a query
  behind it. „Gut gemacht!" is not a claim and is therefore harmless. A sentence that is neither
  is a bug.
- Dismissible, and dismissal sticks for that type for 7 days. `aria-live="polite"`, never
  `assertive` — a banner must not interrupt a screen reader user mid-table.

### 7.4 Drafted e-mails

Always tier B. The artefact is a **draft in the panel with a copy button and a `mailto:` link**.

**The assistant cannot send e-mail, and this is structural, not a policy:** there is no SMTP
client and there will not be one (decision-23's dependency budget). A human therefore reads every
word before it leaves. That is the entire wrong-answer defence and it is stronger than any check.

Additional rules: every figure in a draft is a template slot filled from SQL, and the §7.1
verifier runs over the finished draft. Recipient addresses are chosen by the director from
`contacts` in a normal `<select>`; a model-produced e-mail address is never used, never
auto-filled, and never even displayed.

### 7.5 Suggested operating procedures

The assistant may *propose* a gbrain note when it notices the director repeating a correction
(„die letzten fünf `auto_closed`-Schichten wurden alle auf 5 h 45 gesetzt — soll das eine Regel
werden?"). It is tier B, it lands as a **draft** note attributed and dated, and it is inert until
the director accepts it. An SOP the assistant wrote and nobody read is exactly the drift §6.1
exists to prevent.

---

## 8 · Cost and latency

| when | what runs | model calls | cost | user-visible latency |
|---|---|---|---|---|
| **every page load** | one `SELECT` from `assistant_insight` | **0** | 0 | sub-ms |
| **nightly, 04:15** | 6 aggregates + insight phrasing (+ watchlist evaluation, §9.3) | 1–2 | ≈ ½ cent/tenant/day | none — nobody is awake |
| **on demand, per turn** | 1 planning call + ≤ 4 tool calls + 1 answering call | ≤ 2 | 1–4 cents | 2–6 s, with a real progress line |

Hard limits, all enforced in `lib/assistant/budget.js`, all failing **closed**:

- ≤ 4 tool calls per turn. The fifth is a refusal, not a loop.
- 30 s wall clock per turn; 3 s `statement_timeout` per query; `max: 2` read connections.
- Token cap per turn, and a **daily spend cap per tenant** in `app_settings`
  (`assistant.daily_cap_millicents`, default 200 = €2/day). Over cap → a plain German sentence
  („Das Tageslimit für den Assistenten ist erreicht."), never a spinner and never a silent
  degradation to a worse answer.
- Nothing may raise its own budget: `POST /admin/settings` is on the tier-D refusal list (§4.2).
- Provider unreachable or slow → the chat says so and the panel is otherwise unaffected. **The
  assistant failing must look like the assistant failing, not like the panel failing.**

Progress line while waiting, because a 6-second spinner on a money screen is its own problem:
„Ich sehe die Schichten vom 1.–31. Juli durch …" — derived from the capability names actually
running, not invented.

---

## 9 · Three surprises

Not in any spec, cheap, no dependency, obviously useful inside a week.

### 9.1 Payroll pre-flight

**Before the CSV button becomes enabled**, the assistant runs a fixed five-item checklist over the
selected period and states pass/fail per item: an open shift inside the period; an unresolved
`auto_closed`; a rate change mid-period; a shift over 8 h; a worker who had shifts last month and
none this month.

The checks are pure SQL and need no model at all — the model only phrases the summary, and §7.1
guards it. It costs five counts and it directly closes audit finding 2, where the CSV can carry a
number the screen already knows is wrong; the checklist is the moment before the mistake becomes a
payslip. It serves the highest-consequence job on the board (JTBD-5) at its single riskiest
instant, and it is useful on day one because the failures it names already exist in the data.

### 9.2 The watchlist — „frag später nochmal"

Any tier-A question can be pinned („sag mir, wenn in der Stiftgasse mehr als 12 Stunden in einer
Woche stehen"), which stores the `(capability, params, threshold)` triple and evaluates it in the
**same nightly job** — surfacing on `/` only when the condition is true.

It reuses machinery that already exists after §7.2 (one table, one loop) and adds no model call at
all on the evaluation path, because a threshold comparison is `>`. It is the feature that turns a
chat into an operations manager: the director's second week is the same five questions as their
first, and this is the difference between answering them and *being told*. Guardrails against
becoming noise: five per tenant, auto-expiry after 60 days unless re-confirmed, and each alert
carries the „Nachrechnen" link so it can be checked in one click.

### 9.3 Paste-a-message → proposed correction

The director gets „hab um 6 angefangen, Handy war leer" on WhatsApp; pasting it into the chat
produces a tier-B proposed shift correction with worker, building and times pre-filled, and the
original message text mirrored into decision-30's required note field.

It is one capability over the existing `POST /admin/shifts` / `PATCH /admin/shifts/:id` endpoints,
so it adds no write path and no dependency. It serves JTBD-2 and JTBD-4 — two of the top four jobs
— and both of those jobs *start* as a message from a worker, so this removes the retyping step
that is the whole job. The provenance is better than the manual path, because the worker's actual
words end up in the audit trail instead of a paraphrase.

### Which I would cut first

**9.3, the paste-a-message feature.** It is the only one of the three where the model *creates*
data rather than *checking* it, and the failure mode is the worst kind: „um 6" transcribed as
06:00 when the worker meant 18:00 is plausible, silent, and lands on a payslip. The same job takes
twenty seconds in the manual shift form that already exists, so the saving is convenience, while
9.1 and 9.2 remove a class of error. **Keep the features that check numbers; cut the one that
invents them.**

---

## 10 · Proving this shipped

Per this project's verification culture: **a check whose negative case cannot fail is not a
check.** Every row below must be shown going RED before it is trusted going GREEN.

| # | check | mutation that must make it FAIL |
|---|---|---|
| V1 | `server/routes/admin.js`'s route table contains **no** `DELETE` on `/admin/shifts` | add `{ method:"DELETE", path:"/admin/shifts/:id" }` → RED |
| V2 | As `nfc_assistant`: `DELETE FROM shifts`, `UPDATE shifts SET …`, and `WITH d AS (DELETE FROM shifts RETURNING *) SELECT * FROM d` all ERROR | `ALTER ROLE nfc_assistant SET default_transaction_read_only = off` → RED |
| V3 | As `nfc_assistant`: `SELECT password_hash FROM admins`, `SELECT token FROM sessions`, `SELECT apple_sub FROM workers`, `SELECT enrolment_code_hash FROM workers`, `SELECT token_hash FROM portal_grants`, `SELECT phone_e164 FROM workers` all ERROR | `GRANT SELECT ON admins TO nfc_assistant` → RED |
| V4 | No `asst_*` view's column list intersects the §4.1 denylist — asserted from `information_schema.columns`, not by reading the SQL | add `email` to `asst_workers` → RED |
| V5 | An unregistered capability id, and a registered one with a bad param, both produce a refusal row and **zero** database statements | make the loop fall through to a default handler → RED |
| V6 | A model reply containing a numeral it was not given never reaches the screen | stub the provider to alter one digit; assert the deterministic template rendered. Remove the verifier → RED |
| V7 | A tier-B execution without a matching `assistant_approvals` row with a non-null `approved_by` is impossible | call the execute path with `approval_id = null` → must 403 → RED if it succeeds |
| V8 | An expired (> 15 min) proposal cannot execute | freeze the clock forward, execute → must 409 → RED |
| V9 | Egress: no payload reaching `fetch` contains a worker name, a building name, an e-mail or a phone number — asserted by intercepting `globalThis.fetch` in the test, on a fixture with known values | remove the pseudonymiser → RED |
| V10 | `ASSISTANT_ENABLED` unset → `/admin/assistant/*` returns 404 and the process boots and serves a clock-in normally | make `instrument`/boot depend on the assistant module → RED |
| V11 | Zero model calls on any page load: intercept `fetch`, load all 7 routes | call the provider from the dashboard handler → RED |
| V12 | Over the daily cap the turn is refused with the German sentence and **no** provider call | remove the budget check → RED |
| V13 | gbrain lint: no corpus file contains a bare 2+ digit number or a currency amount outside a code fence | add „wir haben 4 Mitarbeiter" → RED |
| V14 | gbrain freshness: changing `registry.js` without updating `describes_sha256` fails the build | edit the registry only → RED |
| V15 | de/en key parity across every new key | add a key to `de.json` only → `pnpm check` RED |
| V16 | Every proposal card is operable and its money delta is in the submit button's accessible name | remove the delta from the accessible name → RED |

**Not covered, stated so it is not assumed:** whether the model's *choice* of capability is good
(unmeasurable here — `assistant_approvals.outcome = 'discarded'` is the only honest error-rate
signal, and it needs weeks of use); prompt-injection via data the assistant reads (a worker cannot
write free text into any `asst_*` view today, but `material_requests.note` is a candidate the
moment workers can type into it — see task); and the cost model at 20 tenants, which is
extrapolated, not measured.

---

## 11 · Order of work

Nothing that touches a model exists until the cage does.

```
1  nfc_assistant role + asst_* views + V2/V3/V4 guards      ← no model, no UI, no chat
2  registry + assistant_audit + refusal path (V1, V5)       ← still no model
3  egress boundary: scrub reuse + pseudonymiser (V9)
4  DPA / sub-processor / privacy-policy disclosure          ← BLOCKS enabling in production
5  chat route + drawer UI, German, 390px, a11y (V10, V11, V15)
6  gbrain corpus + check-gbrain.mjs (V13, V14)
7  tier-B proposals + approvals + provenance (V7, V8, V16)
8  budget, caps, kill switch, Sentry (V12)
9  nightly insight + numeral verifier (V6)
10 surprises: pre-flight (9.1), watchlist (9.2), paste (9.3, cut first)
```

Steps 1–3 are the whole security model and they ship **before** anything can be talked into
anything. If the project stops after step 3, nothing has been risked and nothing has been gained,
which is the correct shape for a feature this dangerous.

---

*Written 2026-08-12. Spec only. No code changed, no migration written, no route added, nothing
deployed. Production was not read from and not written to.*
