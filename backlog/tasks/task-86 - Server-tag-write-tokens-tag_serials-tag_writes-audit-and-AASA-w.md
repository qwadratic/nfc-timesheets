---
id: TASK-86
title: 'Server: tag-write tokens, tag_serials, tag_writes audit, and AASA /w*'
status: To Do
assignee: []
created_date: '2026-08-12 05:51'
labels:
  - tags
  - server
  - security
dependencies: []
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: medium
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The server half of in-app tag writing (decision-35). No app code here.

'Admin mode' is NOT a mode. A mode is a flag on a device, and a flag on a device is one
setting screen away from a curious worker, or one handed-over phone away from an uncurious
one. It is a CAPABILITY TOKEN:

```
panel (admin session, decision-20) -> POST /admin/tag-write-tokens {location_uuid}
  -> panel renders a QR of  https://<host>/w?k=<token>
  -> phone scans -> App Link opens the app at the write screen, for that ONE location
  -> app GET /tag-write/<token> -> {location_uuid, name, url_to_write, expires_at}
  -> app POST /tag-write/<token>/result {serial, result, previous_uri, bytes_*}
```

Single admin minter, single location, single use, ~15 min TTL. A worker cannot mint one, so a
worker cannot reach the screen. Reuse server/lib/enrolment.js (single-use, TTL'd, normalised
codes with a written entropy argument) and the limiters in lib/auth.js. NO NEW NPM DEPENDENCY
(decision-16, decision-23).

tag_serials: (serial -> location_id). This is nfc/KnownTags.kt's own upgrade path #1 - it
turns tag adoption from a release into an admin action. Serve it with the worker roster.

tag_writes: one row per ATTEMPT (location_id, tag_serial, wrote_at, admin_user, previous_uri,
result, bytes_needed, bytes_capacity). Answers the question nobody can answer today: which
serial is on which wall, and when it last changed. Without it a dead tag is a site visit.

THE AASA CHANGE IS THE DANGEROUS PART. apple.paths is ['/t*']. Adding '/w*' goes through
ops/branding.json + node ops/gen-wellknown.mjs --write + server/wellknown/verify.sh
(decision-24). '/t*' must not be touched in the same edit - that string is what makes every
tag on every wall work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 POST /admin/tag-write-tokens requires an admin session; a worker session gets 401/403 and no token
- [ ] #2 Token is single-use, ~15 min TTL, scoped to exactly ONE location_uuid, and rate-limited by the existing lib/auth.js limiters
- [ ] #3 MUTATION TEST the gate: replay a consumed token -> refused; expired token -> refused; token for location A used to claim location B -> refused. Each must go RED when its check is removed
- [ ] #4 tag_serials table + admin adopt/unadopt, served with the worker roster so adoption needs no app release
- [ ] #5 tag_writes records EVERY attempt including failures and capacity refusals, not only successes
- [ ] #6 AASA gains /w* via ops/branding.json + gen-wellknown.mjs --write; assetlinks/intent-filter path added to match
- [ ] #7 server/wellknown/verify.sh asserts /t* is STILL PRESENT and fails if it is not. Prove it: remove /t* locally and watch verify.sh go RED
- [ ] #8 Zero new npm dependencies in server/package.json
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 check-api.js + server/wellknown/verify.sh green
- [ ] #2 No secret committed; gitleaks + psst pre-commit gates green
<!-- DOD:END -->
