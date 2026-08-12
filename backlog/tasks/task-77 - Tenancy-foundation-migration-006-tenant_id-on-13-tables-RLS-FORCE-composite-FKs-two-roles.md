---
id: TASK-77
title: >-
  Tenancy foundation: migration 006, tenant_id on 13 tables, RLS FORCE,
  composite FKs, two roles
status: To Do
assignee: []
created_date: '2026-08-12 05:49'
updated_date: '2026-08-12 06:14'
labels:
  - backend
  - db
  - security
  - multi-tenancy
dependencies: []
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: high
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implements decision-32 sections 1-8 at the schema level. Design and full SQL sketches: backlog/docs/MULTI-TENANCY.md section 1.

The point: the ~110 SQL clauses in server/routes/admin.js, server/lib/reporting.js and server/lib/auth.js must change ZERO characters. The predicate lives once, attached to the table, not 110 times attached to queries.

Scope, in order:
1. tenants table (id, name, status active|terminated, locale, created_at) and deleted_tenants (tenant_id PK, deleted_at, reason) - the latter with NO foreign key to tenants, deliberately, so it survives the cascade (needed by the restore re-scrub).
2. tenant_id BIGINT NOT NULL DEFAULT 1 REFERENCES tenants(id) ON DELETE CASCADE on every business table (backfills the sole existing tenant), THEN swap the default to current_setting('app.tenant_id', true)::bigint.
3. Composite uniques: locations.slug, shifts.client_uuid, workers.apple_sub, workers.phone_e164, workers.enrolment_code_hash all become UNIQUE (tenant_id, x). shifts_one_open_per_worker_idx gains a tenant_id prefix. admins.email STAYS GLOBAL - it is the login key and admin creation is an operator CLI, not a public endpoint.
4. Composite FKs on the whole graph (shifts->workers, shifts->locations, sessions->admins, location_contracts->{locations,clients}, contacts->clients, material_requests->{locations,inventory_items,workers}, portal_grants->locations, worker_sessions->workers) via UNIQUE (tenant_id, id) on parents.
5. ENABLE + FORCE ROW LEVEL SECURITY and one FOR ALL USING/WITH CHECK policy per table.
6. Roles: nfc_owner (NOLOGIN, owns tables, runs migrations) and nfc_app (LOGIN, NOSUPERUSER, NOBYPASSRLS, NOT owner). REASSIGN OWNED, then grants.
7. resolve_admin_session(text) and resolve_worker_session(text): SECURITY DEFINER, STABLE, SET search_path = public, pg_temp, REVOKE FROM PUBLIC, GRANT EXECUTE TO nfc_app. Return ids only, never rows.
8. app_settings becomes per-tenant; list explicitly any key that stays operator-global.
9. The 8h auto-close systemd timer runs outside any request: decide whether it runs as nfc_owner (unscoped maintenance, probably correct) or loops tenants, and WRITE THE CHOICE INTO THE SQL FILE AS A COMMENT - a future reader will assume the other one.

WHY FORCE matters and why the role split is not belt-and-braces theatre: a table's owner bypasses RLS. runbook-vm-provisioning.md:53 creates exactly ONE role today, so ENABLE ROW LEVEL SECURITY alone would do nothing at all, silently.

WHY WITH CHECK is not optional: USING protects reads. Without WITH CHECK an INSERT/UPDATE can still stamp another tenant's id on a row.

CONSTRAINTS: no BEGIN/COMMIT in the migration file (migrate.js runs psql -1). Migration number 006 may be claimed by decision-31's phone_e164 work - coordinate, renumber, and do not run them in parallel. Rehearse against a restored dump in nfc_demo, NEVER against nfc. Production is read-only.

The flag day is /etc/nfc/env switching DATABASE_URL to nfc_app. That switch is the rollback point: point it back at the owner role before deleting anything.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration applies cleanly to a restored production dump in nfc_demo, and the row counts of all 13 tables are unchanged afterwards
- [ ] #2 Every existing table has tenant_id NOT NULL, relrowsecurity, relforcerowsecurity and at least one policy - proved by the registry query in MULTI-TENANCY.md section 1.7, which returns zero rows
- [ ] #3 No file under server/routes/ or server/lib/ (other than db.js) changed a single SQL clause as part of this task
- [ ] #4 Cross-tenant FK insert is rejected by the database, demonstrated: inserting a shift whose location_id belongs to another tenant raises a foreign key violation, not a silent success
- [ ] #5 nfc_app is confirmed NOT owner, NOT superuser and NOT BYPASSRLS by querying pg_roles and pg_class.relowner
- [ ] #6 resolve_admin_session has SET search_path and EXECUTE revoked from PUBLIC - asserted, not assumed
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-08-12 06:14
---
MIGRATION NUMBER ALLOCATION (planning run, 2026-08-12): three designs each wrote "migration 006" - phone identity (TASK-121, decision-31), zones (TASK-78, decision-33) and this one. Allocation by planned ship order: 006 = phone identity, 007 = zones, 008 = tenancy. This task renumbers to 008. Never run two of them in parallel against the same database.
---
<!-- COMMENTS:END -->
