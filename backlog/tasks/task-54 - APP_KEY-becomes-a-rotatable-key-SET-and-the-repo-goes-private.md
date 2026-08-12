---
id: TASK-54
title: 'APP_KEY becomes a rotatable key SET, and the repo goes private'
status: To Do
assignee: []
created_date: '2026-08-12 05:02'
labels: []
milestone: m-5
dependencies: []
priority: high
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The live APP_KEY is readable in a PUBLIC GitHub repo (github.com/proximata/nfc-timesheets) at NFCTimeSheets/API.swift:52, android/branding.properties:24, and four more places in HEAD. server/lib/auth.js:37 compares against exactly ONE value, so rotating it bricks clock-in for every worker until Apple AND Play finish review.

Decided 2026-08-12 (D1): flip the repo private now, make the server accept a SET of keys, and rotate as part of the next store release. Zero worker downtime.

Exploitable today: POST /auth/code is gated only by this public key and server/lib/auth.js:297-314 enforces a process-GLOBAL 30-attempts-per-minute ceiling. Any anonymous caller can hold that budget at zero and permanently deny enrolment to real workers.

Note .gitleaks.toml:25 allowlists tsk_[A-Za-z0-9]{16,} by design, so tooling will never flag this. That allowlist is honest and should stay - it just means this cannot be caught mechanically.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gh repo edit proximata/nfc-timesheets --visibility private, confirmed via gh repo view
- [ ] #2 APP_KEY env var parses as a comma-separated SET; server/lib/auth.js accepts any member via safeEqual, still constant-time per candidate
- [ ] #3 check-api.js asserts: old key accepted, new key accepted, unknown key 401, empty set refuses to boot
- [ ] #4 A new key is generated and added to the set on the VM WITHOUT removing the old one
- [ ] #5 ops/REBRAND.md:152 corrected - it currently says edit Branding.swift, but the literal is at API.swift:52, so following the runbook rotates server and Android but NOT iOS
- [ ] #6 Rate limiting on POST /auth/code is per-IP, not process-global
- [ ] #7 DEMO: two curl calls against a running server, one with the old key and one with the new, both 200; a third with a junk key, 401
<!-- AC:END -->
