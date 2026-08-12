---
id: decision-32
title: >-
  Multi-tenancy is a shared schema with tenant_id enforced by Postgres RLS FORCE
  and composite foreign keys - not schema-per-tenant and not database-per-tenant
date: '2026-08-12 05:47'
status: proposed
---
## Context

The system is single-tenant by assumption, not by design: one `admins` table, one set of
`locations`, and 13 business tables whose rows carry no notion of who owns them. The white-label
groundwork of decision-24 (`ops/branding.json`, `ops/REBRAND.md`, `Branding.xcconfig`) is
**branding** — which company's name and signing identity ship in a *build*. Tenancy is the other
axis: which company's *rows* a request may touch. Two tenants can share one branded deployment;
one tenant can have a bespoke build. Conflating them produces a design where adding a customer
requires an App Store release.

The failure being designed against is specific and unrecoverable. This is payroll-adjacent data
about identified employees in the EU. **Cross-tenant leakage cannot be undone** — you cannot
un-show company A their competitor's staff list, wage rates and building addresses.

The objection that shapes the whole design: a shared schema means every existing query needs a
tenant predicate, and that is exactly the change that gets forgotten in one query. It is not
hypothetical. Counted in this repo, ~110 SQL clauses across `routes/admin.js` (63 KB),
`lib/reporting.js` and `lib/auth.js`:

```
17 FROM shifts · 12 FROM locations · 8 JOIN locations · 7 FROM location_contracts
 6 UPDATE workers · 6 JOIN workers · 5 UPDATE locations · 5 FROM workers · …
```

Adding `AND tenant_id = $n` to 110 clauses by hand — renumbering positional parameters as you go,
with no ORM and no compiler (decision-16 has neither) — is 110 chances to be wrong. The 111th
clause, written next month by someone who never read this record, is wrong with certainty.

Full argument, schema sketches, verification plan and the alternatives in
`backlog/docs/MULTI-TENANCY.md`.

## Decision

**Shared schema. `tenant_id` on every business table. Isolation enforced by Postgres Row-Level
Security with `FORCE`, not by predicates in application SQL. Database-per-tenant is retained as a
documented, priced escape hatch; schema-per-tenant is rejected outright.**

1. **RLS instead of hand-written predicates, because the predicate that gets forgotten is a
   predicate that is never written.** The ~110 existing SQL clauses change **zero characters**.
   The predicate lives once, attached to the table.

2. **The runtime role is not the table owner, and every table is `FORCE ROW LEVEL SECURITY`.**
   A table's owner bypasses RLS, and today migrations run as the same role the server connects
   with (`runbook-vm-provisioning.md:53` creates exactly one role), so `ENABLE ROW LEVEL SECURITY`
   alone would do nothing, silently. `nfc_owner` (NOLOGIN, owns tables, runs migrations) is split
   from `nfc_app` (LOGIN, NOSUPERUSER, NOBYPASSRLS, not owner).

3. **Fail closed.** `current_setting('app.tenant_id', true)` is NULL when unset, so a missing
   context yields **zero rows, not all rows**. Policies are `FOR ALL USING (…) WITH CHECK (…)` —
   `WITH CHECK` is not optional, or a write can stamp another tenant's id on a new row.

4. **Context is transaction-local on a held connection, never a bare `SET` on a pooled one.**
   `withTenant(id, fn)` acquires a client, `BEGIN`, `SELECT set_config('app.tenant_id',$1,true)`,
   runs, commits, releases. Not `SET LOCAL app.tenant_id = …` — that takes no parameters, and
   string-interpolating it would be the one hand-built SQL statement in a codebase that has none.
   A bare `SET` persists on the pooled connection for whoever gets it next, which is an
   *intermittent* cross-tenant read: worse than none, because it passes every test.

5. **`AsyncLocalStorage` (`node:async_hooks`, stdlib — no new dependency, decision-23's budget
   holds) carries the client**, so `query`/`all`/`one` keep their exact signatures and the call
   sites are untouched. The module-level exports **throw** outside a context. They must never fall
   back to the pool: a silent unscoped query is the bug this whole record exists to prevent.

6. **Composite foreign keys, so a cross-tenant reference cannot be stored.** RLS hides rows; it
   does not stop a tenant-A `shift` carrying a tenant-B `location_id` — FK-legal, invisible to
   both, corrupting both their reports. `UNIQUE (tenant_id, id)` on parents plus
   `FOREIGN KEY (tenant_id, location_id) REFERENCES locations (tenant_id, id)` makes that row
   unrepresentable. This is arity, not enforcement.

7. **Every unique constraint becomes tenant-scoped** (`locations.slug`, `shifts.client_uuid`,
   `workers.apple_sub`, `workers.phone_e164`, `workers.enrolment_code_hash`). Not only for
   correctness: **a global unique index is a cross-tenant existence oracle even under RLS** — the
   row is invisible, the `23505` violation is not. `admins.email` **stays global** on purpose (it
   is the login key, point 9) and keeps its oracle, accepted because admin creation is an
   operator-run CLI, never a public endpoint.

8. **Session lookup runs before a tenant exists, and is solved by two narrow `SECURITY DEFINER`
   functions** (`resolve_admin_session`, `resolve_worker_session`) owned by `nfc_owner`, returning
   ids and nothing else, `SET search_path = public, pg_temp`, `EXECUTE` granted only to `nfc_app`.
   Not by exempting `sessions`/`admins` from RLS, which would leave two tables any handler bug can
   enumerate.

9. **The tenant is never in the URL, never in a header, never in a request body.** It comes from
   the session row and nowhere else. `admins.tenant_id` is the answer and the login form gains
   zero fields — no company code, no pre-auth tenant picker, no `/t/<slug>/…` path. A
   user-controlled tenant identifier would force every request to re-check it against the session,
   i.e. a check that must be right in N places, which is the failure mode this record eliminates.
   This is decision-22's rule ("identity comes from the session, never the body") on a second axis.

10. **Onboarding is one command; a per-tenant tag hostname is a per-tenant app release.** AASA and
    `assetlinks.json` are host-exact and redirects are not followed (decision-4, decision-15); the
    iOS Associated Domains entitlement is a compiled-in literal and stays one (decision-24 §6).
    All shared-deployment tenants therefore share **one** tag host. Multiple `applinks:` entries in
    one build are worse, not better: every new tenant would force a new app release onto every
    existing tenant's workers, on an append-only list that can never shrink.

11. **Offboarding: export first, then a real two-phase delete.** `status='terminated'` (login
    refused, data retained, export available) for a 30-day contractual grace window, then
    `DELETE FROM tenants` with `ON DELETE CASCADE` on every `tenant_id` FK. A soft delete is not an
    Art 17 erasure and must not be described as one. **The tenant is the controller, we are the
    processor** (Art 28) — the 7-year Austrian retention obligation is theirs, so we return the
    data and delete ours rather than keeping an archive.

12. **Backups are addressed by a documented retention window, not by editing backups.** Erased
    from live systems immediately; from backups as they age out within 35 days. Valid only if the
    window is in the DPA and the privacy policy, offsite copies are encrypted at rest, and **a
    restore re-applies the erasure** — which needs `deleted_tenants`, the one table with no FK to
    `tenants`, deliberately surviving the cascade.

13. **The landing page is a hand-written static HTML file served by the same Node process**
    (decision-16 unstrained): `/start` now via `routes/landing.js` mirroring `routes/wellknown.js`,
    `/` on a marketing host once the operator-owned domain exists. German first, no JS, no build
    step, no npm dependency. It goes in `server/public-pages/`, **not** `server/wellknown/` — that
    directory is byte-compared against the live host by `verify.sh` and is not somewhere to put a
    marketing file.

14. **decision-15's revisit trigger has fired.** It said to move to an operator-owned tag domain
    "before the first paying client, or before tag count exceeds what can be rewritten in one
    cleaning round." Multi-tenancy is that moment. Buy the domain before tenant #2 — the window
    closes permanently once tags are on another company's walls, when a host move becomes a site
    visit to every building of every tenant.

**Rejected: schema-per-tenant.** It looks safest and is the worst of the three. Isolation rides on
`search_path` — the identical pooled-connection footgun as a GUC, but it **fails open**: a missing
or mistyped schema falls through to the next entry, and the next entry is `public`, which holds
somebody's data. N schemas × 13 tables makes every migration N chances to strand tenants on
different schema versions under one code path. Its only genuine win, a clean per-tenant dump, is
obtainable from a shared schema with `COPY (SELECT … WHERE tenant_id = $1)`.

**Deferred, not rejected: database-per-tenant, and VM-per-tenant.** Database-per-tenant has
genuinely the strongest isolation — no query crosses a database boundary, so the property is not
enforced by us at all. It loses on arithmetic: a pool per tenant meets `max_connections` (100) at
~10 tenants on one VM, cross-tenant operator reporting needs `postgres_fdw`, and one migration
becomes N with N failure states — against decision-1 and decision-16's "one box, one deploy".
VM-per-tenant is total isolation at O(n) operations forever (n certs, n backup jobs, n restore
tests, n Postgres upgrades, n deploys), and decision-24 already makes it cheap to *configure*.
Both stay as **priced options** for a tenant whose works council or client contract demands
physical separation.

## Consequences

**Good.**

- Leakage is prevented by five structures rather than by discipline: a non-owner role under FORCE,
  a NULL-defaulting GUC that fails closed, transaction-local scoping, composite FKs that make the
  bad row unrepresentable, and tenant-scoped unique indexes that close the violation oracle.
- IDOR closes itself. `GET /admin/shifts/9182` for another tenant's id returns 404 with no handler
  code, and that 404 is byte-identical to a genuinely missing id, so ids are not enumerable — the
  same reasoning `routes/portal.js` already applies to revoked vs unknown tokens.
- **Isolation and erasure are the same structure.** The `tenant_id … ON DELETE CASCADE` FK that
  makes isolation checkable is what makes deletion complete. Neither can drift away from the other,
  and a table missing from the cascade has already failed the isolation check.
- Every request becomes one transaction — which TASK-59 wanted anyway.
- Zero new npm dependencies on the server (`AsyncLocalStorage` is stdlib) and zero on the web side.
  The export is `psql \copy` + `tar`. decision-23's budget of `pg` + `@sentry/node` is untouched.

**Costs and accepted limits.**

- **One email administers exactly one tenant.** An accountant serving two companies needs two
  logins. Named so nobody bolts on a subdomain scheme; the upgrade path is an `admin_tenants` join
  table with a picker shown **after** authentication, never before.
- **A slow handler holds a pooled connection for its whole life.** `ponytail:` ceiling is
  `PG_POOL_MAX` (10) concurrent requests. At 5–40 users per tenant that is not close. Upgrade path
  is raising the pool, then splitting long reads out.
- **No cross-tenant operator UI.** Support is a named `psql` session over SSH. Zero code, and three
  tenants do not justify an impersonation subsystem. When support becomes daily, build impersonation
  that mints an ordinary tenant-scoped session, requires a typed reason, writes `impersonation_log`,
  and — the part that makes it acceptable — **is visible to the tenant's own admin in their own UI**.
- **A migration with a flag day.** `006_tenancy.sql` (renumber if decision-31's migration lands
  first — do not run them in parallel) ends with `/etc/nfc/env` switching `DATABASE_URL` to
  `nfc_app`. That switch is the rollback point. Rehearse against a restored dump in `nfc_demo`,
  never against `nfc`. TASK-57 (a restore that has actually been executed) is a practical
  prerequisite.
- **A one-cleaner-two-employers picker becomes necessary** on the worker apps, because
  `phone_e164` is now unique per tenant and one confirmed phone can map to N worker rows. It sits
  **after** OTP verification, so it reveals nothing to someone who does not hold the phone. Without
  it the lookup is ambiguous and someone will "fix" it with a `LIMIT 1`, which is a silent
  wrong-tenant clock-in.
- **`X-App-Key` becomes a cross-tenant secret.** It is unchanged in nature — `lib/auth.js` already
  states it is a coarse gate meaning "this is our app", never identity — but a leak now spans every
  customer instead of one. Strengthens TASK-54's argument; adds no new one.
- **Sentry retention must be set to ≤ the backup window** and events tagged with `tenant_id`, and
  the DPA schedule must list it as a sub-processor.

**Verification, and it must be mutation-proved** — a check whose negative case cannot fail is not a
check, and this project has been bitten three times:

- A **registry check** over `pg_class` / `pg_policies` / `information_schema.columns` asserting that
  every table outside `{tenants, deleted_tenants, schema_migrations}` has a `NOT NULL tenant_id`,
  `relrowsecurity`, `relforcerowsecurity` and ≥1 policy. This is what covers tables that do not
  exist yet: a future migration adding an unprotected table fails CI on the day it is written.
- A **red-team check** as `nfc_app` inside tenant A: no B rows readable, `UPDATE`/`DELETE` of B rows
  affect 0 rows, `INSERT` stamped B is rejected by `WITH CHECK`.
- Four mutations that must each go RED: drop a policy; `NO FORCE` + connect as owner; connect as
  `nfc_owner`; `set_config(…, false)` instead of `true` (assert the *next* pool checkout sees no
  tenant).
- A **grep gate**: `set_config('app.tenant_id'` may appear in `server/lib/db.js` and nowhere else —
  crude, ~5 lines, and it closes the one bypass the runtime role genuinely has.
- A **post-erase check** driven by the same registry (not a hand-written table list), mutation-proved
  by flipping one FK to `ON DELETE SET NULL`.

**Relationships.** Supersedes nothing. Extends **decision-22**'s session-not-body rule to the tenant
axis. Fires **decision-15**'s own revisit trigger (buy the operator-owned tag domain). Constrains
**decision-24** by drawing the branding/tenancy line explicitly: `branding.json` is per-deployment,
tenant display name is per-row. Holds **decision-16** (one box, one process, no framework, no ORM),
**decision-23** (dependency budget), **decision-1** (no Docker) and **decision-2** (Postgres).
Overlaps **TASK-61** (GDPR erasure path) — the individual-worker Art 17 path is pseudonymisation of
`workers` with `shifts` untouched, and belongs there rather than being built twice.

**Not decided here, on purpose.** Whether to build any of it now. Production holds 8 shifts, 4
workers, 1 location; there is no tenant #2. Building this before a signature is speculative, and
building it after tags are on tenant #2's walls is a migration under load. The single item with a
hard deadline is the domain purchase.

