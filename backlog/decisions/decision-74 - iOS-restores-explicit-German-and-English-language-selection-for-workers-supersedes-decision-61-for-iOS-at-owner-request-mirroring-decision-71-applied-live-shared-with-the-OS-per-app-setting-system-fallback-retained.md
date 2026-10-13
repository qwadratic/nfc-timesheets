---
id: decision-74
title: >-
  iOS restores explicit German and English language selection for workers -
  supersedes decision-61 for iOS at owner request, mirroring decision-71 -
  applied live, shared with the OS per-app setting, system fallback retained
date: '2026-10-07 08:06'
status: accepted
---
## Context

decision-61 (2026-08-29) removed Android's in-app language switcher so that both platforms
followed the OS language only. decision-71 (2026-09-22) reversed that "for Android only at
owner request", and PR 6/7 shipped it: `AppLanguage.kt`, `ui/LanguagePicker.kt`,
`res/xml/locales_config.xml`. decision-71's body is empty - its title is the whole record -
so the behaviour below is read from the Android source at `60f6886`, not from that record.

That left the exact asymmetry decision-61 was written to remove, now pointing the other way:
Android has a language control on the sign-in screen and in settings, iOS has none, and
decision-61 as written still forbade one on iOS. The 2026-10-07 divergence analysis
(`8aafbf1..60f6886`, zero commits under `NFCTimeSheets/`) found three items blocked by it.

Owner instruction, 2026-10-07, in chat: the priority is that the new features that appeared on
Android appear on iOS, and any decision record that requires is to be recorded. This is that
record.

What Android does at `60f6886`:

- three options, in this order: `Deutsch`, `English`, `Wie am Telefon` / `Use phone language`,
  under the title `Sprache` / `Language` (`strings.xml` keys `language_title`, `language_de`,
  `language_en`, `language_system`); a radio group, exactly one selected
- the stored value is one of `""`, `"de"`, `"en"` and nothing else (`AppLanguage.set` `require`s it)
- on Android 13+ the control writes the OS-OWNED per-app locale
  (`LocaleManager.applicationLocales`), so the in-app control and the system per-app language
  setting are one value and can never disagree; below 13 it is a private preference
- placement: the signed-out screen under the brand block (`TimeSheetApp.kt:228`) and its own
  card in settings (`TimeSheetApp.kt:2193`)
- reach: every screen including the operator and scan activities (`LocalizedActivity`), every
  formatted date, time and hours figure, and the shift reminders (`ShiftSignals.strings`)
- it is device-local: no server call, survives sign-out and restart, and switching neither
  signs the worker out nor touches a running shift

## Decision

1. The iOS app gets the same control with the same three options, the same order, the same
   copy and the same value set (`""`, `"de"`, `"en"`). `""` means "follow the phone" and is
   the default; it behaves exactly as iOS behaves today.
2. Placement mirrors Android: on the signed-out screen under the brand block, and as its own
   section in settings after the identity section.
3. ONE source of truth, shared with the OS, as on Android 13+: the choice is the app's per-app
   language value - the same value the app's own Language row in iOS Settings reads and
   writes - not a second private flag beside it. A language chosen in iOS Settings shows as selected in
   the app, and the reverse. Choosing "follow the phone" removes the override rather than
   storing a third state.
4. It applies LIVE, in the running process, without a relaunch: screens, operator screens,
   dates, times and numbers. Text iOS renders ahead of time is re-rendered on change - the
   locally scheduled shift reminders (decision-10) are re-armed in the new language, because
   iOS fixes a notification's text when it is scheduled, where Android reads it when it fires.
5. Switching language is never in the tap path and never mutates state: it must not sign the
   worker or the operator out, touch a running shift, a material draft or the pending write
   queue, or delay, block or reorder a clock-in.
6. One resolver, `AppLanguage.swift`, Foundation-only so `NFCTimeSheets/checks/` can run it
   the way it runs `TagLink.swift`: it maps the stored value to a locale and to the string
   table for that language. Every user-visible string resolves through it. That is enforced by
   a CHECK wired into `checks/run.sh`, not by convention - a `String(localized:)` that bypasses
   the resolver is a build-time failure of that check, the same way `localisation-check` fails
   on a missing German entry.
7. No agent edits `project.pbxproj` or the entitlement for this (decision-49). `knownRegions`
   and `developmentRegion` stay the owner's, under TASK-327.
8. NOT ported, on purpose: Android derives the "this week" boundary from the display language
   (`WeekFields.of(AppLanguage.locale(...))`, `TimeSheetApp.kt:2106`). On iOS a total must not
   change because the UI language changed; the week boundary stays `Calendar.current`.

Supersession: decision-61 rule 1 ("no in-app switcher anywhere") is superseded for iOS. With
decision-71 it is now superseded on every platform. decision-61 rule 2 STANDS: decision-8 is
unchanged, German is the default language, full de + en parity is required, and what an
unsupported phone language falls back to is untouched here (TASK-327).

## Consequences

- The asymmetry is removed by adding the control to iOS, not by taking it from Android - the
  opposite of decision-61's trade, at the owner's direction. A worker who cannot read German
  gets a visible door on the first screen, which is what TASK-258 asked for on Android.
- Cost on iOS: about 164 `String(localized:)` call sites across 15 files resolve from the main
  bundle today and have to go through the resolver, and SwiftUI views need the locale in their
  environment. That touches nearly every file, so it lands as a FOUNDATION change before the
  screen ports that add new strings, not alongside them.
- Rule 3 and rule 4 pull against each other: the OS per-app value is read once per launch, so
  the live switch needs the resolver on top of it. If the Simulator shows a surface that cannot
  follow a live switch, that surface says so in words until the next launch; it does not
  silently stay in the old language, and it does not justify a second source of truth.
- New ported screens use format styles (`Date.formatted`, `.number`), never a fixed-locale
  `DateFormatter` or `String(format:)` with a literal unit, or they will ignore the choice.
- There is no Live Activity extension target yet, so nothing there follows the choice; when the
  owner adds it (`docs/LIVE-ACTIVITY-SETUP.md`), its strings come from a catalogue the resolver
  can reach, not a hardcoded German sentence.
- Verification is on the Simulator, driven, per AGENTS.md: switch on the signed-out screen,
  switch with a shift running, switch with a material draft open, relaunch, change it in iOS
  Settings and reopen, and read a re-armed reminder.
