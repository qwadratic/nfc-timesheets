---
id: TASK-79
title: >-
  withTenant() in db.js: AsyncLocalStorage context, session-to-tenant
  resolution, and query() throws outside a context
status: To Do
assignee: []
created_date: '2026-08-12 05:49'
updated_date: '2026-08-12 05:52'
labels:
  - backend
  - security
  - multi-tenancy
dependencies:
  - TASK-77
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: high
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The runtime half of decision-32. Design: backlog/docs/MULTI-TENANCY.md section 1.4 point 3, with a working sketch.

server/lib/db.js gains:

  withTenant(tenantId, fn) - validates the id is a positive integer, pool.connect(), BEGIN,
    SELECT set_config('app.tenant_id', $1::text, true), runs fn inside an AsyncLocalStorage
    context holding the CLIENT, COMMIT / ROLLBACK, release in finally.

  query/all/one - unchanged signatures, but they read the client from the context and THROW
    when there is none.

NON-NEGOTIABLES, each of which is a specific bug being prevented:

- set_config(name, value, is_local=true), NOT 'SET LOCAL app.tenant_id = ...'. SET LOCAL takes no parameters; interpolating the id would be the one hand-built SQL statement in a codebase that has none.
- is_local MUST be true. A bare SET persists on the pooled connection and is inherited by the next request - an INTERMITTENT cross-tenant read, which is worse than none because it passes every test.
- query/all/one must THROW outside a context, never fall back to the pool. A silent unscoped query is the exact bug decision-32 exists to prevent.
- AsyncLocalStorage from node:async_hooks. Stdlib. No new dependency (decision-23 budget: pg + @sentry/node, nothing else).

Wiring:
- Admin routes: session cookie -> resolve_admin_session(token) -> {admin_id, tenant_id} -> withTenant(tenant_id, handler). The tenant comes from the session row and NOWHERE else - not the URL, not a header, not the body (decision-32 point 9, extending decision-22).
- Worker routes: resolve_worker_session(token) the same way.
- Unauthenticated routes that touch the DB (portal.js): the grant row itself carries the tenant. Resolve the grant in a bootstrap step, then withTenant. Keep the 404-for-revoked-and-unknown behaviour byte-identical.
- Sentry: tag events with tenant_id in lib/scrub.js. Never put row data in an event.

CONSEQUENCE TO ACCEPT AND DOCUMENT IN THE FILE: every request becomes one transaction (TASK-59 wanted this anyway), and a slow handler holds a pooled connection for its whole life. ponytail: ceiling is PG_POOL_MAX (10) concurrent requests; at 5-40 users per tenant that is not close. Upgrade path: raise the pool, then split long reads out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 withTenant is the ONLY place in server/ where the string set_config('app.tenant_id' or SET LOCAL app.tenant_id appears - enforced by a grep gate in the check suite
- [ ] #2 query/all/one throw a named error outside a tenant context; a test asserts the throw, not a result set
- [ ] #3 A test proves transaction-local scoping: after a withTenant block completes, the NEXT checkout of the same pooled connection sees current_setting('app.tenant_id', true) IS NULL
- [ ] #4 Mutation proof: changing set_config's third argument from true to false makes that test go RED
- [ ] #5 No route handler reads a tenant id from req.url, headers or the request body - verified by review and by a grep for tenant_id in server/routes/
- [ ] #6 No new npm dependency: server/package.json still lists exactly pg and @sentry/node
<!-- AC:END -->
