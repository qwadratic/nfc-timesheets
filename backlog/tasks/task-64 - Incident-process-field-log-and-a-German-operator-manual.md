---
id: TASK-64
title: 'Incident process, field log, and a German operator manual'
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-5
dependencies: []
priority: medium
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three PM gaps that share a root: nothing connects what happens in a Vienna stairwell to this repo.

NO incident process. The 2026-08-11 adopted-tag / cannot-clock-out incident was handled entirely ad hoc - visible as commit 217bf96 and as task-49's parenthetical. No incident record, no timeline, no severity, no postmortem, and nothing tells the director what to do when a worker cannot clock in at 06:00. backlog/docs/ has 18 files and not one is an incident log.

NO feedback channel. task-47 diagnoses it: the only channel is phoning the director, so the director learns about it from a payroll number that looks wrong weeks later. task-49 is the current state of the art - manually pulling a screen recording out of a Telegram chat. Heroic one-off, not a channel.

NO customer-facing docs. Every document in the repo is developer-facing. The single operator-facing artifact is a Worker rollout checklist at android/README.md:582 - buried at line 582 of a 30 KB engineering document, in ENGLISH, for a German-speaking Vienna cleaning company.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 backlog/docs/INCIDENTS.md: three severities in this product's terms (S1 a worker cannot clock in/out or hours are lost; S2 the director cannot run payroll; S3 cosmetic), response expectation per level, append-only log
- [ ] #2 The 2026-08-11 event retro-filed as INC-001 - it is fresh and well understood, which makes the template concrete
- [ ] #3 backlog/docs/FIELD-LOG.md with a fixed template (date, who, device, expected, actual, tag id) and a standing weekly triage that converts entries into tasks
- [ ] #4 A one-page GERMAN worker card: install, enrol with the code, tap, what Gesendet means, what to do if nothing happens
- [ ] #5 A GERMAN director guide: issue an enrolment code, correct a shift, run payroll, read the client portal. Extract from android/README.md:582 and backlog/docs/ADMIN-WALKTHROUGH.md, which already hold the content
- [ ] #6 A printed escalation card for the director
<!-- AC:END -->
