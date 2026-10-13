---
id: TASK-367
title: Company-bound AI tools API and MCP integration
status: Done
assignee:
  - '@codex'
created_date: '2026-10-10 18:40'
updated_date: '2026-10-10 18:49'
labels: []
dependencies: []
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Allow external AI assistants to discover and execute company administration with revocable company-bound access. No voice or chat UI; future messaging adapters reuse this integration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Credentials bind one active company and admin with scopes expiry and revocation; cross-company access rejected.
- [x] #2 Typed tools cover company business operations with documented platform and account exclusions.
- [x] #3 REST tools and stdio MCP reuse existing handlers with audited writes and retry protection.
- [x] #4 Real integration tests verify isolation and business operations; connection instructions documented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Company-bound credentials and CLI. 2. Comprehensive typed tool catalog. 3. REST dispatch with audit and retry protection plus stdio MCP bridge. 4. Real PostgreSQL HTTP tests, branding and independent decision review. 5. Fork branch and upstream PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified on disposable local PostgreSQL using restricted RLS role: 53/53 company tools exercised through HTTP; real stdio MCP bridge lifecycle and calls; two-company isolation; read-only restrictions; expiry/revoke; concurrent, failed and pending retries; encrypted secret replay; one audit per mutation; forced worker/operator code collision retry. Existing check-workspaces PASS; catalog 4/4 PASS; MCP bridge PASS; branding OK with no TODO/FAIL. Independent decision and code review approved after savepoint correction. Legacy check-api has identical single adopted-serial 200-vs-409 failure on clean origin/main 190d423 and this branch. check-sms-flag hits identical Windows psql role -v invocation error on clean main and branch. No production deploy or real external messages.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented company-bound revocable access, 53 typed admin tools, REST API and dependency-free stdio MCP bridge, durable encrypted retry results and atomic append-only audit. Added CLI issuance/revocation, two migrations, CI checks and connection/tool documentation. Feature checks pass; baseline legacy test limitations recorded. Ready for fork PR; production deployment remains separate.
<!-- SECTION:FINAL_SUMMARY:END -->
