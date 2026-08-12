---
id: TASK-125
title: >-
  Retire Sign in with Apple: /auth/apple returns 410, and guideline 4.8 gets
  read before it is claimed
status: To Do
assignee: []
created_date: '2026-08-12 06:14'
labels:
  - server
  - ios
  - security
milestone: m-6
dependencies:
  - TASK-124
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
priority: medium
ordinal: 125000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH implementation step 10 and open item 1. Deliberately NOT bundled with TASK-123 -
turning off the old door and building the new one in the same deploy means a failure has two
possible causes.

    POST /auth/apple  ->  410 Gone
    server/lib/apple.js deleted ONE RELEASE LATER, not in the same commit
    workers.apple_sub  KEPT as an audit column

OPEN ITEM 1, and it is the one thing that could reverse decision-31: the claim that a first-party
phone login does not trigger the App Store guideline 4.8 Sign in with Apple requirement is
UNVERIFIED. Read the current guideline text and record the quote, with a date, before the next
submission. Do not submit on the assumption.

ALSO NAME A DATE (open item 5): between TASK-123 and this task, THREE enrolment mechanisms coexist -
SMS, enrolment code, Sign in with Apple. decision-26s "two paths to keep correct" quietly becomes
three. That window needs an end date written on it here.

JOB: none directly. This is debt retirement, and its value is that every future auth bug has one
fewer place to hide.

MUST NOT REGRESS: no worker is locked out. Every worker with an apple_sub must have a confirmed
phone number BEFORE the 410 ships - that is the gate, not a nice-to-have.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A query proves every worker who has ever signed in with Apple now has phone_confirmed_at set - run BEFORE the 410 ships
- [ ] #2 POST /auth/apple returns 410 with a German message telling the worker what to do instead
- [ ] #3 The current guideline 4.8 text is quoted verbatim with its retrieval date in the task notes
- [ ] #4 The transition end date for the three coexisting enrolment mechanisms is written into the task and into decision-31s notes
- [ ] #5 lib/apple.js deletion is a SEPARATE release, referenced from this task, not done inside it
<!-- AC:END -->
