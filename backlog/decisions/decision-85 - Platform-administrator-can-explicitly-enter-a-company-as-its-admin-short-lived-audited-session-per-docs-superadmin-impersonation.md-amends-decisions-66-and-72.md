---
id: decision-85
title: >-
  Platform administrator can explicitly enter a company as its admin -
  short-lived audited session per docs-superadmin-impersonation.md - amends
  decisions 66 and 72
date: '2026-10-20 18:20'
status: proposed
---
## Context

decision-66 reserved tenant 0 for platform administrators and named "click-to-view-as-tenant" as its own future decision. decision-72 lets the platform create companies and invite their owners, but says platform admins do not IMPLICITLY act as a company admin. Support still has no way to look at or fix a company's workspace without asking the owner for a password.

## Decision

Proposed: a superadmin may ENTER a company explicitly from `/platform/` (TASK-379, `docs/superadmin-impersonation.md` on the work branch).

- `POST /platform/workspaces/:id/enter` creates a session OF that company's first `admin` (lowest id) with `sessions.impersonator_admin_id` = the superadmin. RLS scope, composite admin references and every company rule apply unchanged. TTL 1 hour. The owner's own sessions are untouched.
- The platform session token waits in a second `ts_platform` cookie (same HttpOnly, Secure, SameSite=Strict flags). `POST /admin/impersonation/exit` revokes the company session and restores the platform session only if that token is a live, non-impersonating session of the same superadmin; otherwise both cookies are cleared. Logout from inside revokes both.
- A company with no `admin` account (owner never redeemed the invitation) cannot be entered; the platform never mints a company credential for itself.
- Inside a company: a persistent banner names the company, the acting account, the platform account and the expiry; `POST /admin/password` answers 403 `impersonation_forbidden`; platform routes answer 401.
- The session stops resolving the moment its opener is no longer a `superadmin`; deleting that account cascades the rows away.
- Audit (decision-65): `impersonation.started` and every non-GET request inside are written to the COMPANY's `action_log` with origin `superadmin`, actor = the superadmin, target = the impersonated admin.
- Both routes are listed as never delegated in the agent catalog (decision-79).

## Consequences

- Migration 029 adds `sessions.impersonator_admin_id` (nullable FK to `admins`, ON DELETE CASCADE).
- Support can act in a company without its password, visibly and on the record; anything done there is attributable to the platform account.
- Agent tokens still have no HTTP minting route, so none can be created from inside an entered company.
- Status stays proposed until the owner accepts it.
