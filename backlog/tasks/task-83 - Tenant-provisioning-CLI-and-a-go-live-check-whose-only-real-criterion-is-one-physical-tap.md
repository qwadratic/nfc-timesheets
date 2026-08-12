---
id: TASK-83
title: >-
  Tenant provisioning CLI and a go-live check whose only real criterion is one
  physical tap
status: To Do
assignee: []
created_date: '2026-08-12 05:50'
updated_date: '2026-08-12 05:52'
labels:
  - backend
  - ops
  - multi-tenancy
dependencies:
  - TASK-77
  - TASK-79
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: medium
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Onboarding, decision-32 point 10 and MULTI-TENANCY.md section 2.

server/bin/create-tenant.js - mirrors the existing server/bin/create-admin.js in shape and style. Creates the tenants row, creates admin #1, mints a SINGLE-USE invite token, prints the invite link.

It must NOT print or mail a password. A password the operator has seen is a password the operator can use, and the tenant is a different legal entity whose employees' data this protects.

server/bin/check-tenant.js - the go-live gate. Asserts the tenant has >=1 location, >=1 admin, >=1 confirmed worker and >=1 SHIFT ROW.

The shift row is the only criterion that cannot be faked from a chair. Nothing except a physical tap proves the chain tag -> universal link -> AASA -> app -> session -> shift. This project has already shipped a whole Android app verified end to end on an emulator that has no NFC radio (BACKLOG-TRIAGE list A #2). The other three criteria are inventory; this one is evidence.

DELIBERATELY NOT BUILT: a CSV importer for locations. Ten buildings is ~20 minutes of typing done once, the Locations CRUD already exists, and an importer is code nobody needs. Build it when a tenant arrives with >50 locations. ponytail: state this in the file so the next person does not add it reflexively.

Also in scope: a one-page ops/ONBOARD-TENANT.md runbook listing the 8 steps from MULTI-TENANCY.md section 2.1 and marking which are automated, which are manual and which are physical. It must state the section 2.2 boundary plainly - on the shared deployment a tenant gets a display name and their own data, NOT their own app, icon, bundle id or tag hostname, because those are properties of a build (decision-24), not of a row.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 create-tenant.js creates tenant + admin + single-use invite token in one transaction, and prints no password or password hash
- [ ] #2 Running create-tenant.js twice with the same admin email fails cleanly with a readable message, not a raw 23505
- [ ] #3 check-tenant.js exits non-zero when any of the four criteria is unmet and names which one
- [ ] #4 check-tenant.js cannot be satisfied without a real shift row - verified by running it against a tenant with locations, admins and workers but no shifts, and seeing it fail
- [ ] #5 ops/ONBOARD-TENANT.md exists, marks each step automated/manual/physical, and states the shared-deployment boundary from MULTI-TENANCY.md section 2.2
- [ ] #6 No new npm dependency
<!-- AC:END -->
