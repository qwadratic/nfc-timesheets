# Platform administrator enters a company

Decision: decision-85. Builds on decision-66 (tenant 0 = platform, impersonation deferred to
its own decision) and decision-72 (platform admins do not IMPLICITLY act as a company admin).
Entering is explicit, visible, short-lived and audited.

## Behaviour

- `/platform/` lists companies with `admin_count`. "Enter company" is enabled only when the
  company has at least one `admin` role account. A company whose owner has not redeemed the
  invitation cannot be entered; the platform never creates a company credential for itself.
- `POST /platform/workspaces/:id/enter` (superadmin only) creates a NEW `sessions` row for the
  company's first `admin` (lowest id) with `impersonator_admin_id` = the superadmin. The session
  is the company admin's own, so RLS scope, composite admin references and every company rule
  apply unchanged. TTL is 1 hour (ordinary admin sessions: 7 days). The owner's own sessions
  are untouched.
- The superadmin's platform token is parked in the `ts_platform` cookie (same HttpOnly, Secure,
  SameSite=Strict flags as `ts_session`).
- `GET /admin/session` returns `impersonator: { email, company, expires_at }`; the web shell
  shows a persistent banner on every company page with a "Back to platform" button.
- `POST /admin/impersonation/exit` revokes the company session and restores the platform
  session only if the parked token is a live, non-impersonating session of the SAME superadmin.
  Otherwise both cookies are cleared and the user lands on sign-in.
- `POST /admin/logout` from inside a company revokes both sessions.
- A company session opened by an account that is no longer `superadmin` stops resolving
  immediately; deleting that account cascades the rows away.

## Limits inside a company

- `POST /admin/password` answers `403 impersonation_forbidden`: the platform never takes over
  a company's credentials.
- Platform routes answer 401 inside a company (the session's role is `admin`).
- Agent tokens have no HTTP minting route (decision-79), so none can be created from inside.

## Audit

`action_log` (decision-65), in the COMPANY's tenant, `origin = 'superadmin'`,
`actor_id` = superadmin id, `target_table = 'admins'`, `target_id` = impersonated admin id:
`impersonation.started` on enter, and `METHOD /path` for every non-GET request made inside,
including the exit itself.

## Verification

`node server/check-workspaces.js` against loopback PostgreSQL runs `check-impersonation.js`:
enter/refuse, scope, audit, credential guard, exit, forged exit, logout, opener demotion and
removal. The password guard and the opener-role clause were each mutated and the check failed.
