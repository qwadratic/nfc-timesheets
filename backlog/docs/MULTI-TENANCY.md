# Multi-tenancy and the landing page — design

**Status: design only. Nothing here is implemented.** Companion decision record: `decision-32`
(status `proposed`).

| task | | |
|---|---|---|
| TASK-76 | buy an operator-owned tag domain before tenant #2 | blocked on owner · §2.4 |
| TASK-77 | tenancy foundation — migration, RLS FORCE, composite FKs, two roles | §1.4, §1.8 |
| TASK-79 | `withTenant()` in `db.js` — AsyncLocalStorage, throws outside a context | §1.4-3, §1.5 |
| TASK-81 | isolation check suite, mutation-proved, registry-driven | §1.7 |
| TASK-83 | tenant provisioning CLI + go-live check | §2.1 |
| TASK-85 | offboarding — export, two-phase erasure, restore re-scrub | §3 |
| TASK-88 | **`ux`** landing page | §4 |
| TASK-90 | **`ux`** multi-tenant login + two-employer worker picker | §5 |

Dependency order: `77 → 79 → {81, 83, 90}`, `77 → 85`. TASK-76 and TASK-88 are independent.

The system is single-tenant by assumption, not by design. One `admins` table, one set of
`locations`, one `shifts` table with no notion of who owns a row. White-label groundwork exists
(decision-24, `ops/branding.json`, `ops/REBRAND.md`, `Branding.xcconfig`) — that is **branding**:
which company's *name and signing identity* ship in a build. Tenancy is a different axis: which
company's *rows* a request may touch. Two tenants can share one branded deployment; one tenant can
have a bespoke build. They are orthogonal and this document does not conflate them.

Scope of the failure being designed against, stated once:

> This is payroll-adjacent data about identified employees in the EU. **Cross-tenant leakage is
> unrecoverable.** You cannot un-show company A their competitor's staff list, wage rates and
> building addresses. Every other property in this document is negotiable; that one is not.

---

## 1. The tenancy model

### 1.1 The three candidates, argued

| | shared schema + `tenant_id` | schema-per-tenant | database-per-tenant |
|---|---|---|---|
| isolation mechanism | a predicate | `search_path` | the connection |
| failure mode when it goes wrong | wrong rows | **falls through to `public`** | none available |
| migrations | 1 run | N runs, N states | N runs, N states |
| pool cost on one 25 GB VM | 1 pool | 1 pool | N pools |
| cross-tenant reporting | trivial | awkward | needs FDW |
| offboarding delete | `DELETE`+CASCADE | `DROP SCHEMA` | `DROP DATABASE` |

**Schema-per-tenant is the worst of the three here and it is the one that looks safest.** Isolation
rides on `search_path`, which is connection state on a *pooled* connection — the identical footgun
as a shared-schema GUC — but it **fails open**: a missing or mistyped schema falls through to the
next entry in the path, and the next entry is `public`, which holds somebody's data. And N schemas
× 13 tables turns every migration into N independent chances to end up with tenants on different
schema versions while one code path serves all of them. Its only real win — a clean per-tenant dump
for offboarding — is obtainable from a shared schema with `COPY (SELECT … WHERE tenant_id = $1)`.
Rejected.

**Database-per-tenant has genuinely the strongest isolation**: there is no query that reaches across
a database boundary, so the property is not enforced by us at all. It loses on arithmetic. Each
Postgres backend is a process; a pool per tenant on a single small VM meets `max_connections`
(default 100) at roughly ten tenants, at which point the answer is more VMs, i.e. option four.
It also makes any operator-level question ("how many taps happened last week across all customers")
impossible without `postgres_fdw`, and turns one migration into N migrations with N failure states —
against decision-1 and decision-16's "one box, one deploy, one thing to keep alive".

**Fourth option, named because it is the honest one for a nervous tenant: VM-per-tenant.** decision-24
already makes this cheap to *configure* — `branding.json`, `REBRAND.md`, `runbook-vm-provisioning.md`.
Isolation is total. Cost is O(n) operations forever: n TLS certs, n backup jobs, n restore tests, n
Postgres major upgrades, n deploys. Notably, the NFC hostname cost (§2.4) is *unavoidable* on this
option rather than *additional* — a dedicated VM comes with a dedicated host anyway. **Keep it as a
priced option, not as the default.** An Austrian works council (Betriebsrat) or a larger client may
contractually demand physical separation; when they do, the answer already exists.

### 1.2 The choice

**Shared schema, `tenant_id` on every business table, isolation enforced by Postgres Row-Level
Security with `FORCE`, tenant set per request via `set_config('app.tenant_id', …, true)` inside a
transaction on a checked-out connection.** Database-per-tenant stays documented as the escape hatch.

### 1.3 The objection this design exists to answer

> "Shared schema means every existing query needs a tenant predicate, and that is exactly the kind
> of change that gets forgotten in one query."

Correct, and it is not a hypothetical. Counted in this repo:

```
$ grep -hoE '\b(FROM|JOIN|INSERT INTO|UPDATE|DELETE FROM)\s+[a-z_]+' server/routes server/lib -r
17 FROM shifts · 12 FROM locations · 8 JOIN locations · 7 FROM location_contracts
6 UPDATE workers · 6 JOIN workers · 5 UPDATE locations · 5 FROM workers · …
```

~110 SQL clauses across `routes/admin.js` (63 KB), `lib/reporting.js`, `lib/auth.js`. Adding
`AND tenant_id = $n` to 110 clauses by hand, renumbering every positional parameter as you go, is a
change with ~110 chances to be wrong and no compiler to catch any of them. The 111th clause, written
next month by someone who did not read this document, has a 100% chance of being wrong.

**So the design does not do that.** The whole point of choosing RLS over a hand-written predicate:

> **The predicate that gets forgotten is a predicate that is never written.** The 110 existing SQL
> clauses change **zero characters**. The predicate lives once, in the database, attached to the
> table rather than to the query.

That is the argument. Everything in §1.4 is the mechanism that makes it true rather than aspirational.

### 1.4 How leakage becomes structurally hard

Six mechanisms. Each is a *structure*, not a rule someone must remember.

**(1) The runtime role cannot skip the policy.** A table's owner bypasses RLS. Migrations currently
run as the same role the server connects with (`runbook-vm-provisioning.md:53` creates exactly one
role), so `ENABLE ROW LEVEL SECURITY` alone would do **nothing at all, silently**. Split the roles
and force the policy on the owner too:

```sql
CREATE ROLE nfc_owner NOLOGIN;                      -- owns every table, runs migrations
CREATE ROLE nfc_app  LOGIN PASSWORD '…';            -- runtime. NOT owner. NOSUPERUSER. NOBYPASSRLS.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nfc_app;

ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts FORCE  ROW LEVEL SECURITY;       -- applies to the owner as well
```

**(2) No tenant context yields zero rows, not all rows.** `current_setting('app.tenant_id', true)`
returns `NULL` when unset; `tenant_id = NULL` is `NULL`, and a `USING` clause that is not `true`
does not admit the row. Fail-closed. A handler that forgets to establish context returns an empty
list — visibly broken, not quietly wrong.

```sql
CREATE POLICY tenant_isolation ON shifts
  FOR ALL
  USING      (tenant_id = current_setting('app.tenant_id', true)::bigint)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::bigint);
```

`WITH CHECK` is not optional. Without it, `USING` protects reads while an `INSERT`/`UPDATE` can
still write a row stamped with someone else's `tenant_id`.

**(3) The tenant cannot leak between pooled requests.** `pool.query()` checks out an arbitrary
connection. A bare `SET app.tenant_id` persists on that connection and is inherited by whoever gets
it next — an *intermittent* cross-tenant read, which is worse than none, because it passes every
test. So context is only ever set as transaction-local state on a client you hold:

```js
// server/lib/db.js — sketch
import { AsyncLocalStorage } from "node:async_hooks";        // stdlib. No new dependency.
const ctx = new AsyncLocalStorage();

export async function withTenant(tenantId, fn) {
  if (!Number.isInteger(tenantId) || tenantId <= 0) throw new Error("withTenant: bad tenant id");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // SET LOCAL takes no parameters. set_config(name, value, is_local=true) is the
    // parameterised equivalent. Do NOT interpolate the id into a SET LOCAL string —
    // that would be the one hand-built SQL statement in a codebase that has none.
    await client.query("SELECT set_config('app.tenant_id', $1::text, true)", [String(tenantId)]);
    const out = await ctx.run(client, fn);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

export const query = (text, params) => {
  const client = ctx.getStore();
  if (!client) throw new Error("db: query outside a tenant context");   // fail loud, not open
  return client.query(text, params);
};
```

`AsyncLocalStorage` is the reason the 110 call sites do not change: `query/all/one` keep their exact
signatures. Two consequences worth stating up front:

- Every request becomes one transaction. That is a *bonus* — TASK-59 wants transactions — but it
  means a slow handler holds a pooled connection for its whole life. `ponytail:` ceiling is
  `PG_POOL_MAX` (10) concurrent requests; at 5–40 users per tenant that is not close. Upgrade path
  is raising the pool and, only if that stops working, splitting long reads out.
- The module-level `query/all/one` exports must **throw** outside a context rather than falling back
  to the pool. A fallback is a silent unscoped query, which is the exact bug this design prevents.

**(4) A cross-tenant reference cannot be stored.** RLS hides rows; it does not stop a `shift` in
tenant A from carrying a `location_id` belonging to tenant B. That row is FK-legal, invisible to
both tenants, and corrupts both their reports. Composite foreign keys make it unrepresentable:

```sql
ALTER TABLE locations ADD CONSTRAINT locations_tenant_id_key UNIQUE (tenant_id, id);
ALTER TABLE shifts DROP CONSTRAINT shifts_location_id_fkey;
ALTER TABLE shifts ADD CONSTRAINT shifts_location_fk
  FOREIGN KEY (tenant_id, location_id) REFERENCES locations (tenant_id, id);
```

Same treatment for every FK in the graph: `shifts→workers`, `sessions→admins`,
`location_contracts→locations`, `location_contracts→clients`, `contacts→clients`,
`material_requests→{locations,inventory_items,workers}`, `portal_grants→locations`,
`worker_sessions→workers`. This is the strongest single item on the list: it is not enforcement, it
is *arity*. The bad row has nowhere to go.

**(5) An INSERT that forgets `tenant_id` gets the right one.** Column default reads the same GUC, so
the ~10 `INSERT` statements also change zero characters, and `NOT NULL` catches the contextless case:

```sql
ALTER TABLE shifts ADD COLUMN tenant_id BIGINT NOT NULL DEFAULT 1        -- backfill the sole tenant
  REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE shifts ALTER COLUMN tenant_id
  SET DEFAULT current_setting('app.tenant_id', true)::bigint;            -- then swap the default
```

**(6) Every unique constraint becomes tenant-scoped — including for reasons RLS does not cover.**
A **global unique index is a cross-tenant existence oracle even under RLS**: the row is invisible,
but the `23505` unique violation is not. An attacker who can attempt an insert learns whether a
value exists in another tenant. Concretely, from the current schema:

| today | becomes | note |
|---|---|---|
| `locations.slug UNIQUE` | `UNIQUE (tenant_id, slug)` | two companies may both have a "Stiege 3" |
| `shifts.client_uuid UNIQUE` | `UNIQUE (tenant_id, client_uuid)` | idempotency key; global form is an oracle |
| `workers.apple_sub UNIQUE` | `UNIQUE (tenant_id, apple_sub)` | legacy (decision-22 → decision-31) |
| `workers.phone_e164 UNIQUE` | `UNIQUE (tenant_id, phone_e164)` | see §5.4 — one cleaner, two employers |
| `workers.enrolment_code_hash UNIQUE` | `UNIQUE (tenant_id, …)` | break-glass path, decision-26/31 |
| `shifts_one_open_per_worker_idx` | prefix with `tenant_id` | already implied by `worker_id`; index locality |
| `admins.email UNIQUE` | **stays global** | deliberate — it is the login key, §5.1 |

`admins.email` keeps its global uniqueness *and* its oracle, accepted because admin creation is an
operator-run CLI (`server/bin/create-admin.js`), never a public endpoint, so there is nobody to probe
with it.

### 1.5 The chicken-and-egg: resolving a session before the tenant is known

Session lookup happens *before* there is a tenant, so it cannot run inside `withTenant`. Do not solve
this by exempting `sessions`/`admins` from RLS — that leaves two tables any handler bug can enumerate.
Solve it with one narrow `SECURITY DEFINER` function owned by `nfc_owner`, which returns ids and
nothing else:

```sql
CREATE FUNCTION resolve_admin_session(tok text)
RETURNS TABLE (admin_id bigint, tenant_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp                 -- mandatory on SECURITY DEFINER
AS $$
  SELECT s.admin_id, a.tenant_id
  FROM sessions s
  JOIN admins   a ON a.id = s.admin_id
  JOIN tenants  t ON t.id = a.tenant_id
  WHERE s.token = tok AND s.expires_at > now() AND t.status = 'active'
$$;
REVOKE ALL ON FUNCTION resolve_admin_session(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_admin_session(text) TO nfc_app;
```

Sibling: `resolve_worker_session(tok)`. Two functions, ~10 lines each, the only privileged surface in
the system. `SET search_path` is not decoration — a `SECURITY DEFINER` function without it is the
classic Postgres privilege-escalation bug.

### 1.6 What RLS does **not** cover — write it down before someone assumes it does

- **Backups.** One `pg_dump` holds every tenant. §3.4.
- **Sentry.** `lib/scrub.js` must add `tenant_id` as a tag (so an error is attributable) and must
  keep doing what it already does about PII. An event body must never contain another tenant's data —
  which mostly means never logging query results, which is already the rule (decision-23).
- **The static admin bundle.** One export serves all tenants; it must contain no tenant data. It
  currently does not (it fetches everything). Keep it that way — a build-time tenant constant would
  fork the bundle per tenant and quietly break decision-16.
- **`app_settings`** is global today and must become per-tenant, with an explicit list of any keys
  that stay operator-global.
- **The 8h auto-close systemd timer** runs SQL outside any request. It must either run as `nfc_owner`
  (deliberately unscoped, correct here — it is a cross-tenant maintenance job) or loop tenants. Pick
  one **and write the choice into the SQL file as a comment**, because a future reader will assume
  the other one.

### 1.7 Verifying it — and proving the check can fail

Per the project's verification rule: a check whose negative case cannot fail is not a check.

**Check A — the registry check (covers tables that do not exist yet).** Zero rows required:

```sql
SELECT c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname NOT IN ('tenants','deleted_tenants','schema_migrations')
  AND (   NOT c.relrowsecurity
       OR NOT c.relforcerowsecurity
       OR NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.tablename = c.relname)
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns col
                      WHERE col.table_name = c.relname
                        AND col.column_name = 'tenant_id' AND col.is_nullable = 'NO'));
```

This is the item that answers "someone adds a table next year and forgets". They cannot: the new
table appears in this result and the check goes red. Migration 007 that adds a table without RLS
fails CI on the day it is written.

**Check B — the red-team check.** Seed tenants A and B with overlapping-looking data. As `nfc_app`,
inside `withTenant(A)`, for every table assert `count(*) WHERE tenant_id = B` is 0, `UPDATE` of a B
row affects 0 rows, `DELETE` of a B row affects 0 rows, and an `INSERT` stamped `tenant_id = B` is
rejected by `WITH CHECK`.

**Mutation proof — four negatives that must each turn Check A or B RED:**

| mutation | must fail because |
|---|---|
| drop the policy on one table | Check A (missing policy) and Check B (rows visible) |
| `NO FORCE ROW LEVEL SECURITY` on one table, connect as the owner | proves `FORCE` is load-bearing |
| connect as `nfc_owner` instead of `nfc_app` | proves the role split is load-bearing |
| replace `set_config(…, true)` with `set_config(…, false)` | proves the transaction-local scoping is load-bearing; assert the *next* checkout sees no tenant |

**Check C — a grep gate.** `set_config('app.tenant_id'` and `SET LOCAL app.tenant_id` may appear in
`server/lib/db.js` and nowhere else in `server/`. Crude, ~5 lines, and it actually stops the one
bypass the runtime role genuinely has (it can set its own GUC). Mutation: add the string to a route
file, the gate must fail.

**Check D — the tenanted-context gate.** Every route handler that touches the DB runs inside
`withTenant`. Enforced by (3) throwing, plus one test that calls a handler with no context and asserts
the thrown error rather than a result set.

### 1.8 Migration path from today's single tenant

One migration, `006_tenancy.sql` (renumber if decision-31's migration lands first). It is
non-reversible in practice and it must be rehearsed against a restored dump, not against production.

```
tenants row id=1  ←  the existing company
  ↓ add tenant_id NOT NULL DEFAULT 1 to 13 tables (backfills every existing row)
  ↓ swap defaults to current_setting()
  ↓ composite UNIQUEs, composite FKs
  ↓ ENABLE + FORCE RLS, one policy per table
  ↓ create nfc_owner / nfc_app, REASSIGN OWNED, grant
  ↓ resolve_admin_session / resolve_worker_session
  ↓ /etc/nfc/env DATABASE_URL switches to nfc_app     ← the only ops step, and the rollback point
```

The `DATABASE_URL` role swap is the flag day. Rollback is: point it back at the owner role. Do that
**before** deleting the old role, and rehearse the restore first (TASK-57 is a prerequisite in
practice, not just in principle).

---

## 2. Onboarding a tenant, end to end

### 2.1 The steps

| # | step | who | automated? |
|---|---|---|---|
| 1 | contract + Auftragsverarbeitungsvertrag (Art 28 DPA) signed | operator | manual, always |
| 2 | `node server/bin/create-tenant.js --name … --locale de --admin-email …` | operator | **automated** |
| 3 | first admin sets their own password from a single-use invite link | tenant | automated |
| 4 | clients, buildings, contracts entered | tenant admin | manual (self-serve UI) |
| 5 | workers added (name, phone) | tenant admin | manual |
| 6 | workers install the app, confirm phone by SMS OTP (decision-31) | workers | automated |
| 7 | NFC tags written, one per building entrance | operator or tenant | manual + physical |
| 8 | go-live check: one real tap produces one real shift | tenant | manual, and irreplaceable |

**Step 2 is the only thing worth building.** It mirrors the existing `bin/create-admin.js`: create
the `tenants` row, create admin #1, mint a single-use invite token, print the link. It must **not**
print or mail a password — a password the operator has seen is a password the operator can use.

**Step 4 is deliberately not automated.** A CSV importer for a ten-building list is code nobody
needs; the Locations CRUD already exists and ten buildings is ~20 minutes of typing done once. Build
the importer when a tenant arrives with >50 locations, and not before.

**Step 8 cannot be automated and must not be skipped.** Nothing except a physical tap proves the
chain tag → universal link → AASA → app → session → shift. This project has already been bitten by
the Android version of exactly this (a whole app verified on an emulator with no NFC radio,
BACKLOG-TRIAGE list A #2). Ship a `bin/check-tenant.js` that asserts ≥1 location, ≥1 admin, ≥1
confirmed worker and **≥1 shift row** — the shift row is the only criterion that cannot be faked
from a chair.

### 2.2 What a tenant does *not* get on the shared deployment

Say this in the contract, not after the invoice. On the shared deployment a tenant gets a display
name and their own data. They do **not** get: their own app in the App Store, their own app icon,
their own bundle id, their own tag hostname. Those are properties of a **build** (decision-24), not
of a row. Wanting them means a dedicated build, which in practice means a dedicated VM, which is the
priced option from §1.1.

### 2.3 Effort

| path | effort | why |
|---|---|---|
| tenant on the shared host | **low** | one command, self-serve data entry, tags |
| tenant on a vanity tag host | **high**, and blocked on Apple | §2.4 |

### 2.4 The NFC hostname problem, stated honestly

The mechanics, which are not negotiable and are not ours:

- AASA and `assetlinks.json` are fetched from the **exact** host in the tag URI. **Redirects are not
  followed** (decision-4, decision-15).
- The iOS Associated Domains entitlement is a **compiled-in literal** and deliberately so —
  decision-24 §6 keeps it literal because an undefined build setting expands to the empty string and
  ships `applinks:`, killing universal links with a green build.
- Android matches by intent filter in the manifest — also compiled in, also per-host.

Therefore:

```
new tenant, shared host timesheets.exe.xyz  → tags written, works today, no app release   ✓ free
new tenant, own host app.tenant.at          → their DNS CNAME + we serve their well-known
                                              files by Host  (cheap, hours)
                                            + a NEW iOS build carrying their domain
                                            + App Store / TestFlight review                ✗ NOT free
```

iOS accepts multiple `applinks:` entries, so in principle one build carries every tenant's domain.
That is worse, not better: **every new tenant then forces a new app release onto every existing
tenant's workers**, with review latency in the critical path of onboarding, and an entitlement list
that grows forever and can never shrink (the same append-only trap decision-24 §3 documents for the
AASA appID list — dropping a domain bricks installed copies you cannot uninstall).

**∴ per-tenant tag hostname = per-tenant app release. Price it that way or do not offer it.**

**Recommendation, and it is urgent rather than eventual:** all shared-deployment tenants stay on one
tag host. But that host should not be `timesheets.exe.xyz`. decision-15 already argued for an
operator-owned domain (~EUR 10/yr, CNAME to the VM) and set its own revisit trigger: *"before the
first paying client, or before tag count exceeds what can be rewritten in one cleaning round."*
**Multi-tenancy is that trigger firing.** The window is open exactly as long as the tag count is
small, and it closes permanently once tags are on other companies' walls — at that point a host move
is a site visit to every building of every tenant. Buy the domain before tenant #2, not after.

Android is cheaper but is still a release: a new `assetlinks.json` per host plus a manifest change,
shipped on the Play internal track (decision-27), which is faster than App Store review but is not
zero.

---

## 3. Offboarding

### 3.1 Who is who, because it decides everything else

**The tenant is the controller. We are the processor** (Art 28 GDPR). The workers are the data
subjects and their employment relationship is with the tenant, not with us.

Consequence that simplifies our side enormously: the 7-year Austrian retention obligations on payroll
and accounting records (UGB/BAO, ASVG/AZG) are the **tenant's** obligation, not ours. Art 28(3)(g)
says that at end of contract the processor, at the controller's choice, **returns or deletes** the
data and deletes existing copies unless EU or member-state law requires storage. So our job is:
hand it over completely, then delete ours completely. We do not need a 7-year archive and we should
not want one — held data is liability.

This must be written into the DPA, including the backup window from §3.4. Do not discover it at
termination.

### 3.2 Export

Runs first, always. Deleting before a verified export is how a tenant loses their own payroll history
and their own retention compliance in one command.

`ops/tenant-export.sh` — a shell script, zero npm dependencies (`psql` and `tar` are on the VM;
decision-23's budget is `pg` + `@sentry/node` and this adds nothing):

```
\copy (SELECT * FROM shifts WHERE tenant_id = :tid) TO 'shifts.csv' WITH (FORMAT csv, HEADER)
… one per table …
+ LIESMICH.txt   German, plain, one paragraph per file, every column named and explained
+ manifest.json  table → row count → sha256, so the tenant can verify the transfer
```

**Include:** shifts (incl. edits/audit — decision-30), workers with rate history, locations, clients,
contacts, contracts, inventory, material requests, portal grants (as revoked).

**Exclude, deliberately:** `password_hash`, session tokens, OTP challenge hashes, enrolment code
hashes. Those are credentials, not records. Exporting them transfers a liability nobody asked for and
answers no question the tenant has.

CSV, not a proprietary format and not a `pg_dump`: the recipient is an office with Excel and an
accountant, not a DBA.

### 3.3 Deletion — real, and provably complete

Two phases:

```
terminate:  tenants.status = 'terminated'   → login refused, data retained, export downloadable
            ↓ grace window, 30 days, stated in the DPA
erase:      DELETE FROM tenants WHERE id = $1
            ↓ ON DELETE CASCADE on every tenant_id FK
            every business row in every table, gone
```

The grace window exists so a mis-clicked offboarding is recoverable and so the tenant can actually
pull their export. It is also a period during which we still hold their employees' personal data,
which is why it belongs in the contract rather than in a config file.

**Why the FK graph is the right mechanism:** the same `tenant_id … REFERENCES tenants(id) ON DELETE
CASCADE` that makes isolation checkable in §1.7 Check A makes deletion *complete* by construction. A
table that is missing from the cascade is a table that already failed Check A. Isolation and erasure
are enforced by one structure — which is why neither can drift away from the other.

**A soft delete is not an erasure.** `deleted_at IS NOT NULL` under Art 17 is retention with extra
steps. Do not describe it to a tenant as deletion and do not implement it as one.

**Verification, mutation-proved:** seed a tenant, export, erase, then assert `count(*) = 0` for every
table in the §1.7 registry — the registry, not a hand-written list, so a table added later is covered
automatically. Mutation: change one FK to `ON DELETE SET NULL`, the check must go RED.

### 3.4 Backups — the part that gets skipped

The nightly `pg_dump` (TASK-38/TASK-57) contains every tenant. Today's erase does not touch
yesterday's dump. Three positions, one defensible:

- ✗ **Surgically edit the backups.** No. Rewriting a backup is how you end up with a corrupt backup
  and no way to find out until a restore.
- ✗ **Claim immediate erasure everywhere.** Untrue, and it is untrue in writing.
- ✓ **A documented backup retention window.** Erased from live systems immediately; from backups as
  they age out within N days (N = 35 with a 30-day retention). This is the standard, supervisory-
  authority-accepted position, and it is only accepted if three things hold:
  1. **N is documented** — in the DPA and in the privacy policy (TASK-61), not just in a runbook.
  2. **Offsite copies are encrypted at rest.** Once the dump leaves the VM this is required, not nice.
  3. **A restore re-applies the erasure.** Otherwise a restore silently resurrects a deleted tenant's
     workers, and now you have re-created personal data you told someone was gone.

Point 3 needs one durable row, and it is the one row that must **not** cascade away:

```sql
CREATE TABLE deleted_tenants (            -- NO foreign key to tenants. That is the point.
  tenant_id  BIGINT PRIMARY KEY,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reason     TEXT
);
```

The restore runbook gains a mandatory final step: after any restore, re-run the erasure for every row
in `deleted_tenants` that post-dates the dump. Because `deleted_tenants` is itself in the dump only
if the dump post-dates the deletion, keep a copy of it alongside the backups. Mutation-test this by
restoring a dump taken *before* an erase and asserting the tenant is absent afterwards.

### 3.5 Sentry, and a worker's individual erasure request

**Sentry** holds error events with their own retention. Set that retention to ≤ the backup window,
tag events with `tenant_id`, and keep `lib/scrub.js` honest. An old event containing an admin email
is personal data in a US SaaS and is exactly the kind of thing a DPA schedule must list.

**An individual worker's Art 17 request** is a *narrower* path than tenant offboarding and must not
be routed through it. Their shift hours are the tenant's business record under a legal retention
(Art 17(3)(b)); their identity is not. The correct operation is pseudonymisation, not deletion:

```
workers: name → 'Mitarbeiter #37', phone_e164 → NULL, phone_confirmed_at → NULL,
         email → NULL, apple_sub → NULL, enrolment_code_hash → NULL
shifts:  untouched — hours survive, the person does not
```

The request comes to the **tenant**, who is the controller; we execute it on instruction. Overlaps
TASK-61 and should be built there rather than twice.

---

## 4. The landing page

### 4.1 Audience

The owner or office manager of a small Austrian cleaning company, 5–40 staff, who today runs paper
Stundenzettel or a WhatsApp group and adds them up on the last day of the month. Not a developer.
Not enterprise procurement. **On a phone**, having been sent the link by another owner or in a trade
group — which is also why the link preview matters more than the page's desktop layout.

### 4.2 The one promise

> **Ihre Reinigungskräfte halten das Handy an den Aufkleber. Die Stunden stehen fertig in der
> Lohnverrechnung.**

The promise is the *absence of paperwork*. NFC is the mechanism and mechanisms do not sell. Anything
of the form "NFC-basierte Zeiterfassungsplattform" is a description of us, not of their Tuesday.

One promise. Not three. A page that promises time tracking *and* invoicing *and* materials *and*
analytics reads as a page that does none of them.

### 4.3 Structure — one scroll, six blocks

1. **Hero** — the promise, one photograph of a thumb on a sticker by a door, one CTA. No signup form.
2. **In drei Schritten** — tap, work, tap. Three images, three lines. The tap comes first because it
   is the entire product.
3. **Was Sie bekommen** — Stunden, Lohnverrechnung, Kosten pro Objekt, Materialkosten. Four lines.
   Not a twenty-item feature grid; a feature grid is what you write when you have no promise.
4. **Daten und Betriebsrat** — server in the EU, DSGVO, Auftragsverarbeitungsvertrag available, and
   the one that actually wins the meeting: **kein GPS, keine laufende Standortverfolgung** — a tag
   tap at a door, nothing else. Every works-council objection to phone-based time tracking is about
   surveillance. Defuse it before it is raised, in the tenant's own words.
5. **Preis** — a number. A price filters out the wrong conversations before they cost a call. If
   there is no price yet: "Pilotphase: kostenlos, begrenzte Plätze."
6. **Kontakt** — a `mailto:` and a phone number. **No form.** `ponytail:` a form needs a POST
   endpoint, spam handling and a place to store contact PII we would then be the controller for;
   `mailto:` is zero code and already works. Ceiling: no lead tracking, no attribution. Upgrade path
   is one POST route the day the email volume justifies it.

### 4.4 Craft requirements

- **German first.** `<html lang="de">`. English at `/en` if at all. Not next-intl — this is one hand-
  written static file, and next-intl is the panel's concern (decision-17).
- **No new dependency, no build step, no JS.** Hand-written HTML with an inline `<style>`, following
  the existing `server/wellknown/t.html` convention exactly, including its habit of writing the
  measured contrast ratio into a CSS comment. That file is the house style for this artefact; match
  it rather than inventing a second one.
- **Accessibility is a requirement, not a pass.** Single column, real `h1`→`h2` order, CTAs are `<a>`
  not styled `<div>`, every image has alt text that says what it shows, ≥4.5:1 body contrast with the
  ratio recorded in a comment, `prefers-color-scheme`, `prefers-reduced-motion` honoured — best
  honoured by animating nothing. Must be fully usable with JS disabled, which it is, because there is
  none.
- **Open Graph tags plus one OG image.** The distribution channel for this audience is WhatsApp. A
  link with no preview is a link nobody taps.
- **`/robots.txt` and a `/sitemap.xml`, neither of which exists today.** The landing is
  `index,follow`; every panel route and `/t` are `Disallow` (`t.html` is already `noindex`). Without
  this the thing that ranks for the company name is the admin login page.
- **No customer names, no real worker names, no real addresses in any screenshot.** Use the demo
  database (`nfc_demo`, guarded by `demo/check-guards.sh`). This repo has already shipped a real
  client name into a public git blob once (TASK-37); a marketing page is a louder version of the same
  mistake.

### 4.5 Where it is hosted, given decision-16

The collision: `/` already serves the admin panel's dashboard (`web/app/page.tsx`, static-exported,
served by `serveStatic` in `server/server.js`). Four options:

| | option | verdict |
|---|---|---|
| A | landing at `/`, panel moves under a `basePath` | ✗ breaks every bookmark and the login redirect, touches the panel build |
| B | content-negotiate `/` on the session cookie | ✗ too clever. A cookie-varying `/` is a caching and crawler trap |
| C | landing at `/` on a **second hostname**, panel keeps `/` on `timesheets.exe.xyz` | ✓ eventually |
| D | landing at a path, e.g. `/start`, served like `/t` | ✓ now |

**Do D now, C when the domain is bought.** `server/routes/landing.js` mirrors
`server/routes/wellknown.js` — read the file once at boot, serve it at `/start` with a short
`cache-control`, plus a `Host`-header branch that maps `<marketing host>/` to the same bytes. Then
buying the domain (§2.4 says buy it before tenant #2 anyway) is a config line, not a rebuild.

Keep the file **out of** `server/wellknown/`. That directory is byte-compared against the live host by
`verify.sh` and generated by `ops/gen-wellknown.mjs`; adding an unrelated marketing file to the most
dangerous directory in the repo is how a gate gets loosened to accommodate it.

Everything stays on the one VM, in the one process. decision-16 is not strained by this.

---

## 5. The multi-tenant admin login

### 5.1 How an admin lands in the right tenant

**They do not choose. `admins.tenant_id` is the answer, and `admins.email` stays globally unique so
it can be the lookup key.** The login form gains **zero** new fields.

```
email + password → admins row → admins.tenant_id → session row carries tenant_id → withTenant(…)
```

Rejected alternatives, each for a specific reason:

- ✗ **A "Firmencode" field.** A support burden on day one ("what is my company code?"), and probing
  it enumerates the tenant list.
- ✗ **A tenant picker before authentication.** Same enumeration, plus it is a screen shown to someone
  who has proven nothing.
- ✗ **The tenant in the URL** (`/t/<slug>/shifts`) or in a header. This is the important one: it puts
  a **user-controlled tenant identifier in every request**, so every request must re-check it against
  the session — a check that must be correct in N places, which is precisely the failure mode §1 is
  built to eliminate. It also reintroduces the mistake decision-22 already fixed for workers.

> **The tenant is never in the URL, never in a header, never in a request body. It comes from the
> session row and nowhere else.** This is decision-22's rule ("identity comes from the session, never
> the body") applied to the second axis.

**Accepted limitation, named so nobody bolts on a workaround:** one email address administers exactly
one tenant. An accountant serving two cleaning companies, or the operator's own account, needs two
logins. When that becomes real, the upgrade path is an `admin_tenants` join table and a tenant picker
shown **after** authentication — never before, and never in the URL.

### 5.2 What stops an admin reaching another tenant

Five layers, in order of how much code they require (least first):

1. **Nothing reads a tenant from input.** There is no parameter to tamper with.
2. **`withTenant(session.tenant_id)`** wraps the handler; a handler that skips it throws (§1.4-3),
   it does not fall back to an unscoped pool.
3. **RLS `FORCE` + `WITH CHECK`** (§1.4-1,2): reads and writes both.
4. **Composite FKs** (§1.4-4): a cross-tenant reference cannot be stored even by a bug.
5. **IDOR closes itself.** `GET /admin/shifts/9182` where 9182 belongs to tenant B returns **404**
   with no handler code, because RLS returned no row — and the 404 is byte-identical to a genuinely
   missing id, so ids are not enumerable. Same reasoning `routes/portal.js` already applies to revoked
   versus unknown tokens.

### 5.3 Login-surface details that multi-tenancy changes

- **Rate limiting stays global.** `checkLoginRate` is keyed per-email (+IP). It must **not** become
  per-tenant, or an attacker gets one bucket per tenant. This is a one-line mistake that is invisible
  in review unless it is written down first.
- **A terminated tenant fails identically to a wrong password.** "Ihr Unternehmen ist gesperrt" is a
  probe oracle for which companies are customers, and it also tells a fired admin something. Generic
  failure; the operator tells the tenant out of band.
- **Rotate the session token on successful login.** Assert it. Cross-tenant session fixation is the
  version of this bug that matters.
- **Operator cross-tenant access is the real hole.** A superadmin that can set `app.tenant_id` to
  anything is one credential owning every customer's payroll. Two options:
  - ✓ **Now: no cross-tenant UI at all.** Support happens over SSH in a named `psql` session. Zero
    code, and three tenants do not justify an impersonation subsystem.
  - **Later: an impersonation flow** that mints an ordinary tenant-scoped session, requires a typed
    reason, writes an `impersonation_log` row, and — the part that makes it acceptable — **is visible
    to the tenant's own admin in their own UI.** Build it when support is a daily activity, not
    before.

### 5.4 The worker side: one cleaner, two employers

Real in this industry and it will arrive as a support call at 06:00 from someone standing at a door.

Worker identity is a confirmed phone number (decision-31), and §1.4-6 makes `phone_e164` unique
*per tenant*. So one confirmed phone can map to N worker rows. The flow:

```
enter phone → SMS OTP → phone PROVEN
   ↓ 1 worker row  → straight in, no extra screen (the common case stays one screen)
   ↓ N worker rows → pick employer, AFTER verification
```

The picker sits after proof, never before, so it reveals nothing to someone who does not hold the
phone. It is UI work and it is small, but it is not optional: without it the second employer's rows
are unreachable and the OTP lookup is ambiguous — which will surface as a silent wrong-tenant clock-in
if someone "fixes" it with a `LIMIT 1`.

Related: `X-App-Key` is one shared secret across all tenants (decision-24 §9 keeps it out of
`branding.json`). Multi-tenancy does not change what it is — `lib/auth.js` already states it is a
coarse gate meaning "this is our app", never identity — but it does raise the blast radius of a leak
from one company to all of them. That is TASK-54's argument, not a new one; note it there.

---

## 6. Open questions — stated, not papered over

1. **Is there a second tenant?** This design is for a product with customers. The production database
   holds 8 shifts, 4 workers, 1 location. Building §1 before tenant #2 is signed is speculative work;
   building it *after* tags are on tenant #2's walls is a migration under load. The one item with a
   hard deadline is the domain purchase (§2.4) — everything else can wait for a signature.
2. **Which migration number.** `006` is claimed by decision-31's `phone_e164` work. Whichever lands
   second renumbers; do not run them in parallel.
3. **Postgres version.** RLS behaviour assumed here is Postgres 16 (what is deployed). `FORCE ROW
   LEVEL SECURITY` needs ≥9.5, `set_config` is ancient. No version risk, recorded for completeness.
4. **Does the operator want cross-tenant reporting at all?** §1.1 counted it as a win for shared
   schema. If the answer is "no, never", database-per-tenant gets meaningfully more attractive and
   this document should be revisited rather than patched.
5. **Not tested against production and not intended to be.** Production is read-only for this design
   pass. Every SQL fragment above is a sketch to be rehearsed against a restored dump in `nfc_demo`,
   never against `nfc`.
