---
id: m-5
title: Vienna Pilot
status: active
created_date: '2026-08-12'
---

Milestone: Vienna Pilot

## What this milestone means

The existing Vienna cleaning company can rely on this system to record hours and pay
people, without anyone from engineering standing behind it. This is about making ONE
customer trustworthy, not about being sellable to a second one (that is m-6).

Chosen 2026-08-12 over "reliable customer AND shippable product" because the field
evidence says reliability is the unfinished thing: a worker could not clock out on
2026-08-11, and the Android app has never once been run on physical hardware.

## Exit criteria

- [ ] **Both platforms proven on physical tags.** A real iPhone and a real Android
      phone, app fully closed, tapped against a real tag on a real wall, shift lands
      on the server. Emulators and `adb install` do not count — `uses-feature nfc`
      is a Play store filter only, so an NFC-less emulator runs green.
- [ ] **10 consecutive working days with no lost shift.** Measured, not asserted.
      Requires the metrics rollup (M7) to exist so the claim is checkable.
- [ ] **The director completes a payroll run unassisted.** No engineer in the loop,
      no SSH, no explanation. Observed once, end to end.
- [ ] **A worker can report a problem from inside the app.** Today the only channel
      is phoning the director, so failures surface weeks later as a wrong payroll
      number.
- [ ] **Offsite backup exists and a restore has actually been executed.** The current
      `pg_dump` lands on the same disk as the database, which is not a backup.
- [ ] **Sentry is receiving events from production.** `SENTRY_DSN` is currently unset
      on the live VM, so every production error since first deploy has gone nowhere.
- [ ] **Money is auditable.** Rate changes and shift edits leave a record of who,
      when, and what the previous value was.

## Explicitly deferred to m-6

Play Console listing, white-label / second operator, staging environment, CI,
rollback-capable deploy, GDPR erasure path. These are real and filed, but they do
not make the current customer more reliable.
