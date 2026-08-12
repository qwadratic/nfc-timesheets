---
id: TASK-85
title: >-
  Tenant offboarding: export, two-phase erasure, and a restore that re-applies
  the erasure
status: To Do
assignee: []
created_date: '2026-08-12 05:51'
updated_date: '2026-08-12 05:52'
labels:
  - backend
  - ops
  - gdpr
  - multi-tenancy
dependencies:
  - TASK-77
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: medium
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-32 points 11-12, MULTI-TENANCY.md section 3. Overlaps TASK-61 (GDPR privacy policy / erasure path) - coordinate, do not build the individual-worker path twice.

ROLES, because they decide everything else: the tenant is the CONTROLLER, we are the PROCESSOR (Art 28). The 7-year Austrian retention on payroll and accounting records (UGB/BAO, ASVG/AZG) is the TENANT's obligation, not ours. Art 28(3)(g): at contract end the processor returns or deletes at the controller's choice and deletes existing copies. So: hand it over completely, then delete ours completely. We should not want a 7-year archive - held data is liability.

1. EXPORT, always before deletion. ops/tenant-export.sh - psql \copy per table to CSV with header, plus LIESMICH.txt (German, one paragraph per file, every column explained) and manifest.json (table -> row count -> sha256 so the tenant can verify the transfer). tar czf. psql and tar are on the VM; zero npm dependencies.
   INCLUDE: shifts with the edit/audit trail (decision-30), workers with rate history, locations, clients, contacts, contracts, inventory, material requests, portal grants marked revoked.
   EXCLUDE DELIBERATELY: password_hash, session tokens, OTP challenge hashes, enrolment code hashes. Credentials are not records; exporting them transfers a liability nobody asked for and answers no question the tenant has.
   CSV not pg_dump: the recipient is an office with Excel and an accountant, not a DBA.

2. TWO-PHASE ERASURE. tenants.status='terminated' (login refused, data retained, export available) for a 30-day grace window, then DELETE FROM tenants WHERE id=$1 and let ON DELETE CASCADE do the rest.
   The grace window exists so a mis-clicked offboarding is recoverable and so the tenant can actually pull their export. It is also a period in which we still hold their employees' personal data, which is why it belongs in the DPA, not in a config file.
   A SOFT DELETE IS NOT AN ERASURE. deleted_at IS NOT NULL under Art 17 is retention with extra steps. Do not implement it as one and do not describe it to a tenant as one.

3. BACKUPS - the part that gets skipped. The nightly pg_dump (TASK-38/TASK-57) holds every tenant, so today's erase does not touch yesterday's dump.
   DO NOT surgically edit backups. Rewriting a backup is how you get a corrupt backup and find out at restore time.
   DO document a retention window: erased from live immediately, from backups as they age out within 35 days. Only defensible if (a) the window is written in the DPA and the privacy policy, (b) offsite copies are encrypted at rest, (c) A RESTORE RE-APPLIES THE ERASURE.
   (c) needs the deleted_tenants table (created in the tenancy foundation task) - the one table with NO foreign key to tenants, so it survives the cascade. Keep a copy of it alongside the backups, since a dump predating a deletion cannot contain the tombstone. The restore runbook gains a mandatory final step.

4. SENTRY: retention set to <= the backup window, events tagged tenant_id, listed as a sub-processor in the DPA schedule.

5. INDIVIDUAL WORKER Art 17 (belongs in TASK-61, referenced here so it is not routed through tenant offboarding): pseudonymise, do not delete. workers.name -> 'Mitarbeiter #37', phone_e164/phone_confirmed_at/email/apple_sub/enrolment_code_hash -> NULL; shifts untouched. Hours are the tenant's business record under a legal retention (Art 17(3)(b)); the identity is not. The request goes to the tenant, who is the controller; we execute on instruction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Export produces CSV + LIESMICH.txt + manifest.json with per-table sha256, and contains zero credential columns - asserted by grepping the output for password_hash, token and code_hash
- [ ] #2 Post-erase check asserts count(*) = 0 for every table derived FROM the section 1.7 registry, not from a hand-written list
- [ ] #3 Mutation proof: flipping one tenant_id FK to ON DELETE SET NULL makes the post-erase check go RED
- [ ] #4 A restore rehearsal is actually executed: restore a dump taken BEFORE an erase, run the re-scrub step, assert the tenant is absent afterwards
- [ ] #5 The 35-day backup window and the 30-day grace window appear in the privacy policy text and in the DPA template, not only in a runbook
- [ ] #6 Offsite backup copies are encrypted at rest (coordinate with TASK-38/TASK-57 rather than inventing a second mechanism)
- [ ] #7 Runs against nfc_demo only; production untouched
<!-- AC:END -->
