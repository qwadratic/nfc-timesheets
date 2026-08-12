---
id: TASK-89
title: >-
  iOS SPIKE: prove a build with formats=[TAG] uploads - throwaway build, no
  feature
status: To Do
assignee: []
created_date: '2026-08-12 05:51'
labels:
  - tags
  - ios
  - risk
dependencies: []
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: medium
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ONE QUESTION, NOTHING ELSE: will an archive of THIS app with
com.apple.developer.nfc.readersession.formats = ['TAG'] pass upload validation?

WHY IT IS ITS OWN TASK AND ITS OWN BUILD. Commit e4ac6e2 removed this exact entitlement key
after App Store error 90778 ('NDEF is disallowed ... TAG is missing in the entitlement').
90778 is an UPLOAD VALIDATION failure - it fires at Transporter/altool time, before any human
review. Cheap to discover. But a build that will not upload blocks EVERY iOS fix riding in
it, and BACKLOG-TRIAGE.md already records that situation once: seven commits stranded, two of
them clock-in reliability fixes.

RULE: the NFC entitlement change ships in a build of its OWN. Never in the same archive as a
clock-in fix, a German string fix, or anything a worker is waiting for.

WHAT THE DOCS SAY (fetched live, cited in ZONES-AND-TAG-WRITING.md 2.1):
  com.apple.developer.nfc.readersession.formats documents exactly ONE possible value today:
  'TAG - Allows read and write access to a tag using NFCTagReaderSession.'
  NDEF is no longer a documented value. e4ac6e2's diagnosis was right.
Documentation is not a submission. This task is the submission.

WHAT MUST NOT HAPPEN: do not add an in-app reader session on the clock-in path. Background
universal-link tap stays the only way a worker clocks in.

HARD RULE: do NOT edit NFCTimeSheets.xcodeproj/project.pbxproj. The owner hand-edits it. If
the capability needs a project change, write down exactly what he must click.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Near Field Communication Tag Reading capability enabled on the App ID in the developer portal; provisioning profile reissued
- [ ] #2 NFCTimeSheets.entitlements gains com.apple.developer.nfc.readersession.formats = ['TAG'] and NOTHING else changes in that file - applinks:timesheets.exe.xyz stays a literal (decision-24)
- [ ] #3 Info.plist gains a non-empty NFCReaderUsageDescription, in German
- [ ] #4 The archive UPLOADS to TestFlight successfully. Record the exact validation output, pass or fail
- [ ] #5 If it FAILS: record the error code and message verbatim in the task notes and in ZONES-AND-TAG-WRITING.md 5.1, and STOP. Do not iterate blind
- [ ] #6 The build contains NO tag-writing feature and NO reader session. Entitlement only
- [ ] #7 project.pbxproj is unmodified (git diff proves it). Any Xcode clicks required are written down for the owner
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 A yes/no answer recorded with the verbatim validation output
- [ ] #2 This build is NOT promoted to testers
<!-- DOD:END -->
