---
id: TASK-124
title: 'iOS and Android sign-in: one phone screen, one code screen, identical on both'
status: To Do
assignee: []
created_date: '2026-08-12 06:14'
labels:
  - ux
  - ios
  - android
milestone: m-6
dependencies:
  - TASK-123
references:
  - backlog/decisions/decision-31.md
documentation:
  - backlog/docs/SMS-AUTH.md
priority: medium
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SMS-AUTH section 9, implementation steps 7 and 8.

Two screens per platform and a nag banner for a worker whose number is not yet confirmed. The flows
must be identical, because the director supports both from the same sentence over the phone.

Resend at 60s, then 120s. Then the voice fallback (TASK-126). The worker in a stairwell at 06:00
with one bar is the design target, not the worker at a desk.

webcredentials lands in ops/branding.json -> ops/gen-wellknown.mjs -> the committed well-known
files, per decision-24. The AASA appID list is APPEND-ONLY.

HARD RULE: NEVER edit NFCTimeSheets/NFCTimeSheets.xcodeproj/project.pbxproj. The owner hand-edits
it. If a new file must join the target, say so in the notes and stop.
The iOS entitlement stays a CHECKED LITERAL - templating applinks: has already killed universal
links once (decision-24).

JOB: JTBD #3 - invite a worker on the spot.

MUST NOT REGRESS: decision-24 gates - node ops/check-branding.mjs and server/wellknown/verify.sh
stay green. Universal links keep working: the tag -> app path is the product.
Android SMS Retriever is NOT used (SMS-AUTH open item 6) - the body carries the Apple suffix and
Android users may copy manually. Revisit only if someone complains.

SEQUENTIAL after TASK-123. The two platforms are PARALLEL with each other.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both platforms: phone screen -> code screen -> session, with resend at 60s then 120s
- [ ] #2 A worker with an unconfirmed number sees the nag banner and can still work - the tap is never blocked by an unconfirmed number
- [ ] #3 webcredentials generated from ops/branding.json into the committed well-known files; check-branding.mjs and verify.sh both green; the AASA appID list only grew
- [ ] #4 project.pbxproj is byte-identical before and after - proven with git diff --stat
- [ ] #5 Evidence: a demo frame per platform of the code screen, and one real end-to-end sign-in on physical hardware
<!-- AC:END -->
