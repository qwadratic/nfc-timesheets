---
id: TASK-123
title: >-
  The OTP trust boundary: lib/sms.js, /auth/sms/start, /auth/sms/verify, and the
  cost bound
status: To Do
assignee: []
created_date: '2026-08-12 06:14'
labels:
  - server
  - security
milestone: m-6
dependencies:
  - TASK-121
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
modified_files:
  - server/lib/auth.js
priority: high
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH sections 3, 4, 6 and 8. Implementation steps 5 and 6. THIS IS WHERE THE CARE GOES -
the mutation tests are the deliverable, not an extra.

TRANSPORT: plain REST fetch to Twilio. NO SDK - server deps stay pg + @sentry/node (decision-23).
OPTIONAL AT BOOT, exactly like SENTRY_DSN: with no credentials configured, SMS_CONFIGURED is false,
the send sink swallows, and the API still boots and still serves a clock-in. Telemetry and messaging
never gate the tap.

THE OTP: 6 digits, 5 minutes, single use, THREE attempts, hashToken("<e164>:<code>").
Six digits is a USABILITY number, not a security one, and the doc says so out loud:
    3/10^6 per challenge x 100 forceable challenges/day = 3e-4/day -> ~6.3 years to 50%,
    at ~8 EUR/day to the owner and 20 phones ringing.
The security comes from the bounds below, not from the digit count.

THE COST BOUND IS STRUCTURAL FIRST: an SMS only ever goes to a number ALREADY IN workers. SMS
pumping and IRSF are closed by construction, not by a threshold. Then, and only then, the
thresholds: 3/hour and 5/day per number, SMS_DAILY_CAP process-wide. Counters in Postgres
(TASK-121) so a restart cannot refill a spend limit.

BREAK-GLASS: the admin code path still mints a session but DOES NOT set phone_confirmed_at.
Two paths, two meanings, never conflated.

MUST NOT REGRESS: decision-22s rule on a second axis - identity comes from the session, never from
the body. The clock-in path stays unaffected: TASK-121s counters and this endpoint must never sit
between a tap and a shift row.

SEQUENTIAL after TASK-121. Touches server/lib/auth.js - do not run alongside TASK-79 (withTenant)
or TASK-90 (multi-tenant login).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 POST /auth/sms/start refuses a number not present in workers, before any Twilio call - proven by asserting zero outbound requests for an unknown number
- [ ] #2 Three wrong codes burn the challenge; the fourth attempt fails even with the correct code
- [ ] #3 Rate limits enforced per number (3/hr, 5/day) and process-wide (SMS_DAILY_CAP), all counted in Postgres; a service restart mid-window does NOT reset them
- [ ] #4 With no Twilio credentials the server boots, POST /t still creates a shift, and /auth/sms/start fails with a clear typed error rather than a crash (decision-23 boot-optional gate)
- [ ] #5 Break-glass admin code mints a session and leaves phone_confirmed_at NULL - asserted
- [ ] #6 All eight named checks in SMS-AUTH section 10 shown going RED by their documented mutation; RED output pasted into the notes
- [ ] #7 No new npm dependency; no credential in any log line or Sentry payload (scrub.js covers the new fields)
- [ ] #8 LIVE SMS end-to-end, blocked on TASK-119: one real message received on a real Austrian handset
<!-- AC:END -->
