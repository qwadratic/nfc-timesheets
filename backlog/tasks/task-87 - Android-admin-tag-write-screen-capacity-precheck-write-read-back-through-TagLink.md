---
id: TASK-87
title: >-
  Android: admin tag-write screen - capacity precheck, write, read-back through
  TagLink
status: To Do
assignee: []
created_date: '2026-08-12 05:51'
labels:
  - tags
  - android
dependencies:
  - TASK-86
  - TASK-42
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: medium
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Android ships tag writing FIRST because it has no gatekeeper: android.permission.NFC is
already in the manifest, nfc/ScanActivity.kt already does foreground reader-mode dispatch and
already reads NDEF. iOS needs an entitlement that failed submission once (TASK for that is
separate and isolated).

BLOCKED ON TASK-42. Android NFC has never executed on real hardware in this project - every
test so far ran on an emulator, which has no radio. Writing cannot be verified before reading
has been.

CAPACITY FIRST, ALWAYS. Our URL is exactly 64 NDEF bytes. The tag already on the wall at HOIV
is a Mifare Ultralight EV1 with 46. It is unlocked and it still cannot hold our URL.
Compute bytes needed from the EXACT url the server handed back - never a constant, because
the host is white-labelled and a longer host changes the number.

```kotlin
val ndef = Ndef.get(tag)     // null -> try NdefFormatable (a blank NTAG is often unformatted)
ndef.isWritable              // false -> refuse
ndef.maxSize                 // 'maximum NDEF message size in bytes', no RF activity
ndef.writeNdefMessage(msg)   // NOT on the main thread; throws FormatException / TagLost / IO
```

WHEN IT DOES NOT FIT the refusal is not an apology, it is the other half of the feature:
  (a) replace with NTAG213 (144 bytes, ~EUR 0.20) - name the part on screen
  (b) ADOPT this tag by serial (TASK-86 tag_serials), showing the cost in the director's
      words first: an adopted tag has no URL, cannot wake a closed app, and only works
      through the in-app Scan screen. Offering that silently is selling a downgrade.
Show BOTH numbers: 'Dieser Tag fasst 46 Bytes, die Adresse braucht 64.'

NEVER call makeReadOnly(). Irreversible, and it destroys the migration insurance decision-15
is built on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Screen is reachable ONLY via a valid server-minted token link. No menu item, no long-press, no version-number tap. Grep the worker UI and confirm zero entry points
- [ ] #2 Capacity precheck before every write: Ndef.isWritable() + getMaxSize() >= bytes needed, computed from the returned URL. Ndef.get() null -> NdefFormatable attempted before refusing
- [ ] #3 Refusal names both byte figures and offers replace-with-NTAG213 or adopt-by-serial, with the adopted-tag cost stated before confirm
- [ ] #4 Read-before-write: our URL for a DIFFERENT location, or a foreign NDEF message, requires an explicit confirm naming what is being overwritten. Previous bytes captured as the undo
- [ ] #5 After writing, the tag is READ BACK and the URI is passed through TagLink.locationId() - the same function the tap path calls - and must equal the expected UUID
- [ ] #6 MUTATION TEST the verifier: (a) write a deliberately wrong UUID -> FAILED; (b) stub read-back to null -> FAILED; (c) remove the tag mid-write -> FAILED and NO success recorded server-side. Each must go RED
- [ ] #7 Every attempt POSTs a tag_writes row, including capacity refusals and verification failures
- [ ] #8 android/checks asserts makeReadOnly() appears nowhere under app/src
- [ ] #9 Strings in strings.xml, German default, no hardcoded literals; 48dp minimum targets; TalkBack live region on the result like ScanActivity already has
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 android/checks green including the new grep and the three mutation cases
- [ ] #2 Verified on one REAL Android phone against one REAL tag. Not an emulator
<!-- DOD:END -->
