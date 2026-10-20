---
id: TASK-379
title: 'Superadmin: enter a company account (impersonation) from /platform/'
status: To Do
assignee: []
created_date: '2026-10-20 18:20'
labels: []
dependencies: []
priority: high
type: feature
ordinal: 312000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Platform administrators can create companies but have no way to see or fix a company's workspace without the owner's password. decision-66 deferred impersonation to its own decision; that decision is recorded alongside this task (docs/superadmin-impersonation.md on the work branch).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A superadmin can enter any company that has an admin account from /platform/ and lands on that company's workspace
- [ ] #2 Inside a company a persistent banner names the company, the acting account and the platform account, with a Back to platform button that restores the platform session
- [ ] #3 The entered session expires after 1 hour, cannot change the password, and stops resolving once its opener is no longer a superadmin
- [ ] #4 Every enter and every non-GET request inside is recorded in that company's action_log with origin superadmin
- [ ] #5 The two new routes are classified as never delegated in the agent catalog; check-workspaces runs check-impersonation and passes on PostgreSQL; DE/EN messages complete
<!-- AC:END -->
