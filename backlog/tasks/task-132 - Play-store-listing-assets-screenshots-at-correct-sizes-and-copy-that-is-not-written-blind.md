---
id: TASK-132
title: >-
  Play store listing assets: screenshots at correct sizes, and copy that is not
  written blind
status: To Do
assignee: []
created_date: '2026-08-12 16:28'
labels:
  - android
  - store
  - ux
dependencies: []
priority: medium
ordinal: 132000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prepare everything the Play listing needs, ANDROID ONLY. The owner was explicit: Apple does not need preparing now.

REQUIRED BY GOOGLE (verify current requirements rather than trusting this list, they change):
  - app icon 512x512 PNG, 32-bit, alpha
  - feature graphic 1024x500
  - phone screenshots, min 2, correct aspect and min edge - and they must be REAL app frames,
    not mockups. demo/record-android.mjs already drives the emulator and produces real frames.
  - short description (80 chars) and full description (4000)
  - the app's own icon currently ships whatever the template generated; check it against the
    Schimmer und Glanz mark in docs/brand/ before shipping something default.

COPY: research comparable listings (Timr, Papershift, Clockodo, ShiftBase and similar German
and Austrian workforce-time apps) for structure and vocabulary, then write ORIGINAL German
copy. Do not translate from English - a listing that reads as translated undercuts a product
sold on being well made. Do not copy a competitor's sentences.

HONESTY CONSTRAINT: the description must not promise what the app does not do. It does not do
payroll - it suggests hours and a figure. It does not do dispatch. Overclaiming in a store
listing is how a first customer arrives with the wrong expectation.

PRIVACY POLICY, DATA SAFETY, CONTENT RATING are separate obligations already noted against
task-43: the app collects worker identity and location-of-work data and the form must be
answered truthfully, which is a design fact worth stating plainly rather than minimising.

BLOCKED BY task-43 and the account approval task - assets can be prepared in advance, but
nothing can be submitted until the account exists.
<!-- SECTION:DESCRIPTION:END -->
