---
id: TASK-90
title: >-
  Multi-tenant login: admin lands in their tenant with no new field, and one
  cleaner with two employers picks after OTP
status: To Do
assignee: []
created_date: '2026-08-12 05:52'
updated_date: '2026-08-12 05:52'
labels:
  - ux
  - frontend
  - backend
  - security
  - multi-tenancy
dependencies:
  - TASK-77
  - TASK-79
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: high
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-32 point 9, MULTI-TENANCY.md section 5.

ADMIN SIDE - the login form gains ZERO fields.
  email + password -> admins row -> admins.tenant_id -> session row carries tenant_id -> withTenant(...)
admins.email stays globally unique precisely so it can be the lookup key.

Rejected, each for a specific reason (do not reintroduce any of them):
  - a 'Firmencode' field: a support burden on day one ('what is my company code?'), and probing it enumerates the tenant list.
  - a tenant picker before authentication: same enumeration, plus a screen shown to someone who has proven nothing.
  - the tenant in the URL (/t/<slug>/shifts) or in a header: puts a USER-CONTROLLED tenant identifier in every request, so every request must re-check it against the session - a check that must be right in N places, which is exactly the failure mode decision-32 eliminates. It also reintroduces the mistake decision-22 already fixed for workers.

ACCEPTED LIMITATION, stated so nobody bolts on a workaround: one email administers exactly one tenant. An accountant serving two companies needs two logins. Upgrade path when it becomes real: an admin_tenants join table with a picker shown AFTER authentication, never before, never in the URL.

LOGIN-SURFACE DETAILS THAT MULTI-TENANCY CHANGES:
  - checkLoginRate stays keyed per-email (+IP), GLOBAL. It must NOT become per-tenant or an attacker gets one bucket per tenant. One-line mistake, invisible in review unless written down first.
  - A terminated tenant fails IDENTICALLY to a wrong password. 'Ihr Unternehmen ist gesperrt' is a probe oracle for which companies are customers, and it also tells a fired admin something. Generic failure; the operator tells the tenant out of band.
  - Rotate the session token on successful login and assert it. Cross-tenant session fixation is the version of this bug that matters.
  - IDOR closes itself: GET /admin/shifts/9182 for another tenant returns 404 with no handler code because RLS returned no row, and that 404 is byte-identical to a genuinely missing id. Same reasoning routes/portal.js already applies to revoked vs unknown tokens. ASSERT the byte-identical part.

WORKER SIDE - UI WORK, and it is real: one cleaner, two employers.
Worker identity is a confirmed phone number (decision-31) and phone_e164 becomes UNIQUE (tenant_id, phone_e164), so one confirmed phone can map to N worker rows.
  enter phone -> SMS OTP -> phone PROVEN
     1 worker row  -> straight in, no extra screen. The common case stays one screen.
     N worker rows -> pick employer, AFTER verification.
The picker sits after proof, never before, so it reveals nothing to someone who does not hold the phone. It is small but not optional: without it the second employer's rows are unreachable and the lookup is ambiguous - and someone will 'fix' that with a LIMIT 1, which is a silent wrong-tenant clock-in discovered in a payroll argument.

i18n: German is the shipped default. Every new string in web/messages/de.json and en.json with EXACT key parity (pnpm check enforces it). No bare JSX literals. The Android and iOS picker strings go through their own catalogues - and German plurals are whole-string variations, not an appended 's' (TASK-40 is the standing example of getting that wrong).

Panel header shows the tenant display name, so an admin can tell at a glance whose data they are looking at. Read from the session, not from a build-time constant - the static export is one bundle for all tenants (decision-16) and must stay that way.

Accessibility on the picker: it is a list of radio-like choices with a visible focus ring, reachable and operable by keyboard and by screen reader, each option labelled with the employer name. Not a styled div list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Login form has exactly the fields it has today; no company code, no pre-auth tenant selection
- [ ] #2 A valid email+password for tenant A yields a session that can read zero rows of tenant B - proved end to end through the HTTP API, not only at the SQL layer
- [ ] #3 Unknown email, wrong password and terminated-tenant login return byte-identical responses and indistinguishable timing
- [ ] #4 Rate limiting is asserted to be global per-email, not per-tenant - the negative case (N tenants giving N buckets) is explicitly tested and fails
- [ ] #5 Session token rotates on successful login; asserted
- [ ] #6 GET of another tenant's shift id returns a response byte-identical to a nonexistent id - compared byte for byte, not eyeballed
- [ ] #7 Worker OTP with one matching worker row shows NO picker; with two matching rows shows the picker only AFTER successful verification
- [ ] #8 Picker is keyboard operable with a visible focus indicator and every option is labelled with the employer name; verified with keyboard only
- [ ] #9 de.json and en.json have exact key parity and pnpm check is green; no bare JSX literals added
- [ ] #10 Panel header tenant name comes from the session at runtime; the static bundle contains no tenant-specific string
<!-- AC:END -->
