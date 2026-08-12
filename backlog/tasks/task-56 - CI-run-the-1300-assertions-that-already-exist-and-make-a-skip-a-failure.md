---
id: TASK-56
title: 'CI: run the 1300 assertions that already exist, and make a skip a failure'
status: To Do
assignee: []
created_date: '2026-08-12 05:03'
labels: []
milestone: m-5
dependencies: []
priority: high
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repo contains ~1,300 assertions across 15 hand-rolled check harnesses and NOT ONE runs automatically. .github/ does not exist. .githooks/pre-commit runs psst + gitleaks only, and both are behind command -v, so on a machine without them the hook silently passes.

Existing suites: server/check-api.js (132 cases, 601 asserts, boots its own server into a throwaway check_api_PID schema), server/db/check-migrate.js (50), web/scripts/check.mjs (22), NFCTimeSheets/checks/*.swift (227), android/checks/*.kt (277), plus ops/check-branding.mjs, ops/check-autoclose.sh, demo/check-guards.sh, server/check-telemetry-wire.mjs, server/check-close-flag.mjs.

DO THE SKIP FIX FIRST. check-api.js:211-214 and check-migrate.js:24-25 print SKIP and exit 0 when no database is reachable. README.md:257 documents this as a feature, and it is correct for a laptop. The moment CI exists it is dangerous: a misconfigured DATABASE_URL goes green having asserted nothing. Without this fix, CI is theatre.

Also: check-api.js:45 defaults DATABASE_URL with NO loopback check, no host= query check, no PGHOST check, no DB-name check - point it at prod and it CREATE SCHEMAs on the live payroll database. demo/db-guard.mjs already implements exactly these defences and proves them in demo/check-guards.sh (16 cases). Port it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI=1 or REQUIRE_DB=1 turns every SKIP into exit 1 with the same message - land this BEFORE the workflow file
- [ ] #2 demo/db-guard.mjs assertDemoDatabase ported into check-api.js, defeating host= query-param override and PGHOST fallback
- [ ] #3 .github/workflows/ci.yml with a postgres:16 service container runs server, web and ops suites on every push
- [ ] #4 ops job asserts generated well-known files match branding.json: node ops/gen-wellknown.mjs && git diff --exit-code server/wellknown/
- [ ] #5 A single entry point (make check or ops/check-all.sh) fans out to all suites - 13 of 15 are currently unreachable from any package manager
- [ ] #6 The three empty XCTest template files are deleted or filled - they build green and assert nothing, so their presence implies tests that do not exist
- [ ] #7 DEMO: open a PR with a deliberately broken payroll assertion and show CI red; fix it and show CI green
<!-- AC:END -->
