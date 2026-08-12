---
id: TASK-15
title: 'Auth: admin email + password login'
status: Done
assignee: []
created_date: '2026-07-28 13:49'
updated_date: '2026-08-12 04:58'
labels:
  - web
  - auth
milestone: m-3
dependencies:
  - TASK-14
  - TASK-3
priority: high
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PIN login page. POST PIN to server, get session token (JWT or opaque). httpOnly cookie. Server validates on admin endpoints. Single admin PIN same as iOS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Session persists across page refreshes
- [x] #2 Logout clears session
- [x] #3 Login page accepts email + password (decision-20; the PIN is gone)
- [x] #4 Wrong password shows an error
- [x] #5 Correct email + password redirects to dashboard
<!-- AC:END -->







## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Retitled 2026-08-12. decision-20 removed ADMIN_PIN entirely; server/server.js:22 asserts it is deliberately absent and server/check-api.js:508,574 assert it is no longer required. Auth is now scrypt email+password (server/lib/auth.js:6,53,65) against the admins table, created by server/bin/create-admin.js. The original AC#1 'Login page accepts PIN' could never pass and has been replaced.
<!-- SECTION:NOTES:END -->
