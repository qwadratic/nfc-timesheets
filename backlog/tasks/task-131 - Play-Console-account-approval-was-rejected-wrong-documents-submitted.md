---
id: TASK-131
title: Play Console account approval was rejected - wrong documents submitted
status: To Do
assignee: []
created_date: '2026-08-12 16:28'
labels:
  - android
  - blocked-on-owner
  - store
dependencies: []
priority: high
ordinal: 131000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner reported on 2026-08-12 that the Google Play developer account approval is stuck because the WRONG DOCUMENTS were submitted. This blocks task-43 (Play Console listing) and therefore every route to getting the Android app onto a worker's phone other than sideloading.

THIS IS OWNER WORK. An agent cannot submit identity documents. What an agent CAN do is make
the next attempt correct on the first try, because each rejection costs another review cycle.

WHAT TO ESTABLISH (and it is worth being exact, since the requirements differ):
  - which account type was actually chosen. decision-27 recorded PERSONAL, deliberately, so
    no D-U-N-S number is needed. If the signup was completed as an ORGANISATION, that is the
    likely cause of the rejection all by itself, and it is a different document set entirely.
  - for a PERSONAL account Google verifies an INDIVIDUAL: government photo ID in the legal
    name, and an address that matches. A company registration document is the classic wrong
    answer here and will be rejected every time.
  - the name on the ID must match the name on the payment method used for the 25 USD.
  - Austrian specifics: whether a Personalausweis is accepted or a Reisepass is required, and
    whether the address proof must be in German or may be in English.

DELIVERABLE: a short checklist in German the owner can follow once, listing exactly which
document, in which name, in which format, uploaded where - plus what the rejection email
actually said, which is the single most useful input and is not yet recorded anywhere.

ALSO: the owner mentioned a tab open in their Chrome extension relating to this. Ask for it
rather than guessing which console page is meant - there are several and they are not
interchangeable.

DO NOT let this silently block the pilot. Sideloading a signed APK already works
(~/Desktop/NFCTimeSheets-v1.3-scan-inshift.apk) and is the fallback while approval is
pending, so state clearly in the plan that Play is a distribution upgrade, not a dependency.
<!-- SECTION:DESCRIPTION:END -->
