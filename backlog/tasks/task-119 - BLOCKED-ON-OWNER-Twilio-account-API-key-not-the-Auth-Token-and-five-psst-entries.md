---
id: TASK-119
title: >-
  BLOCKED ON OWNER: Twilio account, API key (not the Auth Token), and five psst
  entries
status: To Do
assignee: []
created_date: '2026-08-12 06:12'
labels:
  - blocked-on-owner
  - ops
  - security
milestone: m-6
dependencies: []
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
priority: high
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH section 11. Nobody but the owner can do this: it needs a console login and a payment
method. No agent has or should have Twilio console access.

STEP A - in the Twilio console: create the account, create an API KEY (SID + secret), create a
Messaging Service, and confirm the per-SMS price to Austria (SMS-AUTH open item 4 - SMS_DAILY_CAP
is not final until that number is real).

STEP B - paste into the vault. NO VALUE ON THE LINE: psst prompts, so nothing lands in shell
history or in ps:
    psst set TWILIO_ACCOUNT_SID           --tag server
    psst set TWILIO_API_KEY_SID           --tag server
    psst set TWILIO_API_KEY_SECRET        --tag server
    psst set TWILIO_MESSAGING_SERVICE_SID --tag server
    psst set SMS_DAILY_CAP 200            --tag server

STEP C - psst list --tag server, then sh ops/sync-secrets.sh --dry-run, then sh ops/sync-secrets.sh.

NEVER the account Auth Token (an API key can be revoked without killing the account).
NEVER psst export.

BLOCKS: only the LIVE-SMS acceptance criterion of TASK-123. Everything else in the SMS group is
buildable without a single credential, because lib/sms.js is optional at boot exactly like
SENTRY_DSN (decision-23s pattern).

MUST NOT REGRESS: gitleaks and psst pre-commit gates stay green. No credential in any commit, ever.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Five keys present in psst under --tag server, verified with psst list (names only, never values)
- [ ] #2 An API key is used, not the account Auth Token
- [ ] #3 ops/sync-secrets.sh --dry-run is clean before the real run
- [ ] #4 Per-SMS price to Austria recorded in the task notes so SMS_DAILY_CAP can be finalised
- [ ] #5 gitleaks clean on the working tree afterwards
<!-- AC:END -->
