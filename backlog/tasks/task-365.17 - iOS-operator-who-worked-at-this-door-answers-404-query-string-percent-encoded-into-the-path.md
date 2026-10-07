---
id: TASK-365.17
title: >-
  iOS: operator "who worked at this door" answers 404 (query string
  percent-encoded into the path)
status: To Do
assignee: []
created_date: '2026-10-07 12:22'
labels:
  - ios
  - operator
  - bug
dependencies: []
parent_task_id: TASK-365
priority: medium
ordinal: 301000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### operator-zone-shifts-query-in-path - Operator 'who worked at this door': iOS percent-encodes ?page=N into the path and gets 404  [IOS_BREAKAGE, size S, pre_existing]
- Android at 60f6886: GET /operator/zones/<id>/shifts?page=N built by string concatenation; page renders with paging.
- Android evidence: android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/net/Api.kt:386-387,548; server/routes/operator.js:656-711; server/server.js:94-108
- iOS gap: operatorGet builds URLRequest(url: API.base.appending(path: path)) and zoneShifts passes '/operator/zones/<id>/shifts?page=N' as the PATH (read); Foundation encodes '?' as %3F (server-contract#7 ran a Swift snippet), the server matches on pathname segments, so the answer is 404. Never caught because the screen has only been walked with mocks. Not caused by the range.
- Port notes: Give operatorGet a query parameter and build via URLComponents like apiURL (API.swift:367-373). Foundation-only check that the built URL's path ends in /shifts and query is page=N.

Small and real today: OperatorAPI.swift zoneShifts builds "/operator/zones/:id/shifts?page=N" and the request layer percent-encodes the "?" into the path. Operator-only (outside the worker scope), so deferred - but cheap.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GET /operator/zones/:id/shifts?page=N returns 200 from iOS (page 1 and page 2)
- [ ] #2 A check pins that a query string is never percent-encoded into the path
- [ ] #3 NFCTimeSheets/checks/run.sh is green, including every check this task adds or extends
- [ ] #4 Every new user-visible string has BOTH de and en entries in Localizable.xcstrings in the same commit (AGENTS.md i18n)
- [ ] #5 node ops/check-branding.mjs run and every non-ok / TODO line quoted in the final summary
- [ ] #6 No edit to project.pbxproj or NFCTimeSheets.entitlements (decision-49); Debug and Release builds succeed
<!-- AC:END -->
