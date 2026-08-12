---
id: TASK-61
title: 'GDPR: privacy policy, erasure path, retention, privacy manifest'
status: To Do
assignee: []
created_date: '2026-08-12 05:04'
labels: []
milestone: m-6
dependencies: []
priority: medium
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This system stores EU workers names, emails, phone numbers, Apple sub, and a minute-by-minute record of where each person was and for how long. Findings from the 2026-08-12 audit.

NO privacy policy exists in any language at any URL. web/app/ has no privacy/ or datenschutz/ route; /privacy, /datenschutz and /privacy-policy all 404 (task-43:44-46).

NO erasure path. server/routes/admin.js:359-365 deleteWorker is UPDATE workers SET active=false. Name and apple_sub persist forever. shifts has no ON DELETE CASCADE from workers, so even a manual delete is blocked by the FK.

NO retention policy, no anonymisation (grep for anonymi/retention/Aufbewahr across server/ and web/: zero hits). No DSAR export. No iOS PrivacyInfo.xcprivacy. No DPA with the VM host, and none prepared for Sentry once a DSN lands.

Credit where due: server/routes/portal.js:25-30 limits the client portal to building, date, first name, minutes and explains why. The disclosure boundary is exemplary - the problem is lifecycle, not disclosure.

BLOCKS task-43 (Play Console requires a live privacy policy URL).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 German Datenschutzerklaerung served by the Node process (it already has a static handler at server.js:135) and reachable at a stable URL
- [ ] #2 Erasure: ON DELETE SET NULL on shifts.worker_id plus an anonymisation routine nulling name/email/phone/apple_sub while RETAINING the hours - satisfies GDPR Art.17 and BAO 132 simultaneously
- [ ] #3 Retention policy defined and documented
- [ ] #4 PrivacyInfo.xcprivacy added to the iOS target
- [ ] #5 DPA signed with the VM host; Sentry DPA in place before SENTRY_DSN is set (task-44)
- [ ] #6 DEMO: request erasure for a test worker; show the worker row anonymised and the shift hours still present and still correct in payroll
<!-- AC:END -->
