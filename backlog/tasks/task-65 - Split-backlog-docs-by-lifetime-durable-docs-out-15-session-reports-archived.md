---
id: TASK-65
title: 'Split backlog/docs by lifetime: durable docs out, 15 session reports archived'
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-6
dependencies: []
priority: low
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
backlog/docs/ holds 18 files, ~280 KB. Fifteen are point-in-time AI run reports describing finished work: ADMIN-ITERATION-REPORT, AUTOPILOT-RUN-REPORT, BLOCKER-FIX-REPORT, TAP-FIX-AND-SENTRY, SIWA-REPORT, BACKLOG-TRIAGE, AUDIT-ADMIN-WALKTHROUGH, IN-SHIFT-AND-PARITY, WORKERS-SCREEN, BLOCKER-aasa-host-vs-cloudflare and others.

Worse than untidy: THREE load-bearing documents are buried among them and linked from README. README.md:206 sends you to backlog/docs/runbook-vm-provisioning.md; README.md:232 to backlog/docs/DEMO.md before running the demo seed (which TRUNCATES); README.md:302 to backlog/docs/V2-FEATURES.md for the blocker list. Nothing distinguishes the permanent three from the expired fifteen, and a second developer cannot tell which is still true. AUTOPILOT-RUN-REPORT and BLOCKER-FIX-REPORT describe a state that has been false for over a week.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 runbook-vm-provisioning.md, DEMO.md and V2-FEATURES.md moved to docs/ (which already holds the durable IOS-ANDROID-PARITY.md and LIVE-ACTIVITY-SETUP.md); README links updated
- [ ] #2 The other 15 moved to backlog/archive/docs/ (the tree exists and is empty)
- [ ] #3 A rule in AGENTS.md: session reports go to backlog/archive/docs/ from birth; docs/ is for things that stay true; anything in docs/ carries a Last verified: line
<!-- AC:END -->
