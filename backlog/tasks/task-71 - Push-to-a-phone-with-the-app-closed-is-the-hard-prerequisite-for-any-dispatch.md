---
id: TASK-71
title: Push to a phone with the app closed is the hard prerequisite for any dispatch
status: To Do
assignee: []
created_date: '2026-08-12 05:45'
labels:
  - design
  - ios
  - android
  - server
milestone: m-6
dependencies:
  - TASK-26
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: medium
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md 4.3: every rung of the reliability ladder needs the SERVER to reach a phone whose app is closed. Today no such channel exists.

  APNs (iOS)          not set up - docs/apns-setup.md does not exist (TASK-26)
  FCM (Android)       not set up - the ongoing notification is LOCAL, not server-pushed
  local notification  works, but is scheduled AT CLOCK-IN, so it cannot carry a job that
                      arrives afterwards
  SMS (Twilio)        exists for OTP (decision-31), ~EUR 0.075/msg, SMS_DAILY_CAP default
                      200. A dispatch ladder is ~4 messages per job. Not a dispatch channel.

No push -> dispatch is a phone call -> dispatch is a spreadsheet.

WHY IT IS WORTH DOING ANYWAY. It is the only prerequisite on the list with leverage outside
dispatch: it independently improves the 8h warning, the incident channel (TASK-47) and the
missed-shift nudge. Nothing else on the dispatch prerequisite list does.

SCOPE. TASK-26 is the DOCUMENT (Apple portal, entitlements, provisioning, developer vs
account-owner split). This task is the WORKING CHANNEL on both platforms: device token
registration, a server send path, and one delivered notification per platform observed on
physical hardware.

CONSTRAINTS. Server deps stay pg + @sentry/node (decision-23) - APNs is token-based JWT over
HTTP/2, which node does natively; FCM is an HTTP POST. Neither needs a vendor SDK. Push must
never be required to boot and must never block a clock-in - same rule decision-23 sets for
telemetry. A missing key means push is inert, not that the API is down.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/apns-setup.md exists (satisfies TASK-26) and an equivalent FCM section covers the Android side
- [ ] #2 device tokens are registered per worker and per platform, and are deleted when a worker is deactivated
- [ ] #3 a server send path exists using only node built-ins plus the existing dependency budget - no new npm dependency
- [ ] #4 one push observed arriving on a physical iPhone and one on a physical Android phone, both with the app fully closed
- [ ] #5 with the push credentials absent the API still boots and a clock-in still succeeds; a test proves this and goes RED if a hard dependency is introduced
<!-- AC:END -->
