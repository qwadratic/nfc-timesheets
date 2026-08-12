---
id: TASK-91
title: 'iOS: tag writing via NFCTagReaderSession'
status: To Do
assignee: []
created_date: '2026-08-12 05:52'
labels:
  - tags
  - ios
dependencies:
  - TASK-89
  - TASK-86
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: low
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Only after TASK-89 has proved the entitlement uploads. Feature parity with the Android
screen (TASK-87); every rule there applies here verbatim.

THE EXACT API PATH (cited in ZONES-AND-TAG-WRITING.md 2.1):
  NFCTagReaderSession requires the formats entitlement + a non-empty NFCReaderUsageDescription
  and nothing else. It hands back .miFare(NFCMiFareTag) for an Ultralight EV1. NFCNDEFTag's
  'Inherited By' list is NFCFeliCaTag, NFCISO15693Tag, NFCISO7816Tag, NFCMiFareTag - so
  queryNDEFStatus, readNDEF and writeNDEF are all available on that tag.

  tag.queryNDEFStatus { status, capacity, error in   // capacity: Int, BYTES
      guard status == .readWrite, capacity >= needed else { /* refuse, show BOTH numbers */ }
  }

  Apple's own sample for this job: 'Creating NFC Tags from Your iPhone', iOS 14.0+.

API NOTE: init(pollingOption:delegate:queue:) is marked DEPRECATED. Target
init(configuration:delegate:queue:) or the first build warns and the second breaks.

NEVER call writeLock(). Irreversible; destroys decision-15's migration insurance.

HARD RULE: do NOT edit project.pbxproj.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Writing uses NFCTagReaderSession with init(configuration:delegate:queue:), never the deprecated pollingOption initialiser and never NFCNDEFReaderSession
- [ ] #2 queryNDEFStatus gates every write: status == .readWrite AND capacity >= bytes needed, computed from the server-returned URL
- [ ] #3 Read-back is parsed by the production TagLink.locationId() - the same function the tap path calls - and must equal the expected UUID
- [ ] #4 MUTATION TEST the verifier: wrong UUID, nil read-back, and session invalidated mid-write must each report FAILED and record no server-side success
- [ ] #5 Refusal and adoption behave identically to Android (TASK-87): both byte figures shown, NTAG213 named, adopted-tag cost stated before confirm
- [ ] #6 NFCTimeSheets/checks asserts writeLock( appears nowhere in the tree
- [ ] #7 The clock-in path is untouched: no reader session on tap, background universal link only
- [ ] #8 Strings in Localizable.xcstrings, German default; plural forms use plural VARIATIONS, not appended suffixes (see TASK-40)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Swift checks green including the new grep and the mutation cases
- [ ] #2 project.pbxproj unmodified; any Xcode clicks written down for the owner
- [ ] #3 Verified on one real iPhone against one real tag
<!-- DOD:END -->
