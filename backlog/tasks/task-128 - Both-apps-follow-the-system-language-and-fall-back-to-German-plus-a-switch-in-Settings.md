---
id: TASK-128
title: >-
  Both apps follow the system language, and fall back to German - plus a switch
  in Settings
status: To Do
assignee: []
created_date: '2026-08-12 11:19'
labels:
  - ux
  - ios
  - android
  - i18n
dependencies: []
priority: medium
ordinal: 128000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
REQUIREMENT: system language de -> German. System language en -> English. ANY OTHER system language -> German (not English). Plus a quick language switch on the rightmost tab (Settings) on both platforms.

MEASURED STATE, 2026-08-12 - the two platforms already DISAGREE, and iOS is the wrong one:

  Android  res/values = German (default), res/values-en = English
           de -> de   en -> en   fr -> German     ✓ already correct by construction
  iOS      Localizable.xcstrings sourceLanguage: en, developmentRegion = en
           de -> de   en -> en   fr -> ENGLISH    ✗ wrong fallback

So Android needs no fallback work and iOS does. Do NOT 'fix' Android.

iOS CONSTRAINT, read before planning: the fallback is decided by the development region in
project.pbxproj, and THAT FILE MUST NOT BE EDITED BY AN AGENT - the owner hand-edits it.
Two honest options, pick with reasons:
  (a) an explicit locale resolution in code: read Locale.preferredLanguages, map to de/en,
      German for anything else, and drive lookups from that. Works without touching pbxproj.
  (b) the owner flips the development language in Xcode (write the exact click path).
Option (a) is also what the in-app switch needs anyway, so it probably pays for itself.

THE SWITCH, both platforms, in Settings:
  - two options only. Do not build a locale picker listing languages that do not exist.
  - it must state which one is currently active, including when the choice is 'follow the
    system' - three states (System / Deutsch / English), not two, because a user who has
    never touched it should not see a hard-coded value that happens to match.
  - the choice persists across relaunch and across app UPDATE. Android already keeps its
    session in SharedPreferences with allowBackup=false; put the preference beside it.
  - changing it must re-render without a restart. A setting that needs the app killed to take
    effect will be read as broken.
  - MUST NOT touch the tap path, the sync queue, the session, or the unresolved-shift
    resolver. Language is cosmetic; clocking in is not.

PARITY: iOS catalogue is 112 keys, Android is 134 in values + values-en. Those counts differ
for real reasons (decision-26 gives Android enrolment codes, iOS Sign in with Apple) but the
gap must be EXPLAINED per key, not averaged. Any key present on one platform and missing on
the other is either a genuine platform difference or a hole - say which.

EVIDENCE TO CLOSE: screenshots of both apps under a THIRD system language (French or Polish),
showing German, not English. A claim that the fallback works is not evidence; a locale is the
kind of thing that behaves differently on a device than in a simulator.
<!-- SECTION:DESCRIPTION:END -->
