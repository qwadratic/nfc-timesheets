---
id: decision-30
title: Worker rate history and an audit trail on every money edit
status: accepted
date: '2026-08-12'
supersedes: decision-28
---

## Context

`decision-28` (2026-08-03) shipped contract history and deliberately did **not** ship worker
rate history, on the correct reasoning that `location_contracts` was a new table read by a new
route while `worker_rates` would sit under live payroll for real people. It set a gate: this
record must be moved to `accepted` first, and the accepted version must answer four questions.

Two things changed. First, the gap is a legal one, not only an accuracy one — §26 AZG requires
working-time records and BAO §132 requires seven-year retention of payroll records that
reconstruct what was paid and why. Neither is satisfiable from the current schema. Second, a
separate and worse hole surfaced in the 2026-08-12 audit: `server/routes/admin.js:1070-1110`
(`patchShift`) rewrites a shift's start and end time — which **is** money — recording no
previous value, no actor, and no reason. There is no audit table anywhere in
`server/db/migrations/`.

So the director can today lower a rate or edit a shift, and every historical payroll figure
silently reprices with no record it was ever different.

## Decision

**Ship worker rate history AND an audit trail on every money-affecting admin edit.**

The four questions decision-28 required be answered:

### 1. Does payroll read rate-at-shift-time, or only the reports?

**Both. They read the same source or the director trusts the wrong one.**

`GET /admin/data`'s `hours` aggregate, `server/lib/reporting.js`, and `web/lib/payroll.ts` all
resolve the rate by joining `worker_rates` on the shift's Vienna calendar date. Having payroll
and the P&L disagree about the same worker's cost is worse than having neither be
period-correct, because nothing on screen would say which one is lying.

This also closes P14 from the audit: today `reporting.js:124` rounds per (worker, location)
while `admin.js:228` rounds per worker, so a worker at N buildings diverges by up to
~0.5¢ × (N−1). One shared resolver removes the divergence at its source.

### 2. What rate applies to a shift predating the first `worker_rates` row?

**Backfill makes the question disappear, and makes the migration value-neutral.**

Migration 006 seeds one row per worker: the worker's **current** `hourly_rate_cents`, with
`valid_from` = the earliest of (that worker's earliest shift date, the worker's `created_date`)
and `valid_to` = NULL.

This is the key property: **every existing report reproduces exactly the number it produces
today.** Before the migration all history is valued at the current rate; after it, all history
is still valued at the current rate, because that is the only period that exists. Only *future*
rate changes create a second period. The deploy is arithmetically a no-op, which is what makes
it safe to run under a live payroll.

decision-28 flagged this backfill as "a claim about history nobody verified." It is not a claim
about history — it is a deliberate statement that history *was* valued this way, which is true,
because that is what the code did.

### 3. What happens to `workers.hourly_rate_cents`?

**Kept, as a mirror of the current row.** Not dropped.

This follows the precedent already set in this codebase: `locations.monthly_contract_cents`
mirrors the current `location_contracts` row (`server/routes/admin.js:63-69`). Dropping the
column would change `GET /admin/data`'s response shape and break the shipped iOS build, which
is exactly the live-money blast radius decision-28 was protecting.

The mirror is written in the same transaction as the `worker_rates` insert (see decision-16's
no-ORM constraint — this is a `withTransaction` helper in `server/lib/db.js`, not a framework).
`check-api.js` asserts the two never disagree, the same way it does for contracts.

### 4. Is a rate change retroactive by default?

**No. Two distinct admin actions, because they mean different things.**

- **"Record a raise"** (default) — closes the current period at the chosen date and opens a new
  one. Historical payroll is untouched. This is the common case.
- **"Correct a mistake"** (explicit, second action) — edits the existing period's rate in place,
  because the claim is "this was always wrong." Requires a reason string, and writes a
  `worker_rate_changes` row recording the old value.

The buildings form already had to draw this same distinction for contract prices, so the UI
pattern exists and should be reused rather than reinvented.

### The audit trail

Two append-only tables, written in the same transaction as the change they record:

- `shift_edits` — `shift_id, admin_id, changed_at, old_start, old_end, new_start, new_end, note`.
  Written by `patchShift`. The note is **required**: task-46 already argued that "why it was
  changed" is the part the director actually needs weeks later.
- `worker_rate_changes` — `worker_id, admin_id, changed_at, old_cents, new_cents, reason, kind`
  where `kind` ∈ {`raise`, `correction`}.

Neither table is ever updated or deleted from. Retention is seven years (BAO §132).

## Consequences

- Payroll becomes reproducible: a report printed in April still prints the same numbers in
  September. This is the point.
- A rate change is no longer a single `UPDATE`; it is a transaction. `server/` currently has
  **no** transactions at all (`pool.connect()`/`BEGIN` appear nowhere), so this decision also
  forces the `withTransaction` helper that audit finding P6 needs for contract mutations.
- The admin UI grows a second action on the workers screen and a rate-history view. That is
  new surface and needs its own demo.
- `GET /admin/pl`'s `labour.rate_basis: "current"` marker and its German note, which
  decision-28 required as a permanent visible line, are **removed** once this ships — the
  limitation they describe no longer exists. Leaving them would be a new lie.
- Migration 006 is additive only (expand), so it is safe to apply before the process restart.
  Nothing about it needs a contract phase.
