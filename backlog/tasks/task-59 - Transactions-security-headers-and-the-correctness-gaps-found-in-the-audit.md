---
id: TASK-59
title: 'Transactions, security headers and the correctness gaps found in the audit'
status: To Do
assignee: []
created_date: '2026-08-12 05:03'
labels: []
milestone: m-5
dependencies:
  - TASK-55
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A bundle of small, individually-cheap correctness and hardening fixes from the 2026-08-12 audit. Each is a few lines; none justifies its own task; together they close most of the non-blocker findings.

P6 - contract mutations are multi-statement with NO transaction. pool.connect/BEGIN/COMMIT appear nowhere in server/. createContract (admin.js:744-756) does UPDATE close old period, INSERT new period, mirror. A failure between statements 1 and 2 leaves the building with NO current contract, and reporting.js:251 then silently reports revenue_cents null, no_contract FOREVER. Same shape in deleteContract (:775-783) and syncContractFromLocation (:519-540). Uses the withTransaction helper from task-55.

P11 - no security response headers at all. No CSP, HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy anywhere. A static-export panel cannot set them itself; the Node process must.

P12 - scrypt N=16384 (16 MiB) is below current OWASP guidance (2^17). The stored format is self-describing (auth.js:48) so params CAN be raised, but there is no rehash-on-login path, so existing hashes would stay at the old cost forever.

P15 - email_verified is computed at apple.js:205 and then DISCARDED. routes/auth.js:118-134 binds apple_sub to a workers row on an email match without requiring the address to be verified. One-line guard.

P17 - the payroll CSV silently omits truncated rows. The on-screen caveat (web/app/payroll/page.tsx:315-322) is not carried into the file the accountant keeps.

P18 - server/check-close-flag.mjs greps production SOURCE with regexes, so a benign reformat of routes/app.js breaks the check. Assert the behaviour over HTTP in check-api.js instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 withTransaction wraps createContract, deleteContract and syncContractFromLocation
- [ ] #2 Security headers set in sendJson and serveStatic; verified with curl -I against a running server
- [ ] #3 scrypt N raised with maxmem adjusted, PLUS rehash-on-successful-login in routes/admin.js:134 so existing hashes migrate
- [ ] #4 auth.js refuses the email-match branch unless emailVerified === true; the apple_sub branch is unaffected
- [ ] #5 Payroll CSV either refuses export or carries a leading comment row when periodExceedsCoverage() is true
- [ ] #6 check-close-flag.mjs replaced by an HTTP-level assertion in check-api.js
- [ ] #7 DEMO: curl -I showing the headers; a check-api run proving the contract rollback leaves no orphaned building
<!-- AC:END -->
