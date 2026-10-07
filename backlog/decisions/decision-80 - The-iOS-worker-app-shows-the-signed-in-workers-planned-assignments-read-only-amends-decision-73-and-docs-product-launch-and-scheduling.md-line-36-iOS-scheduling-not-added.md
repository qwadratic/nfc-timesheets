---
id: decision-80
title: >-
  The iOS worker app shows the signed-in worker's planned assignments, read-only
  - amends decision-73 and docs/product-launch-and-scheduling.md line 36 (iOS
  scheduling not added)
date: '2026-10-07 12:59'
status: accepted
---
## Context

decision-73 (accepted, body empty) delegates to `docs/product-launch-and-scheduling.md`. Line 36 of that document says "iOS scheduling is not added in this iteration; its existing NFC behavior is unaffected". That is a scope note for ONE iteration, not a prohibition, and the iteration is over: Android has shown the signed-in worker's planned assignments since TASK-345 / TASK-363 (`GET /me/schedule`, `server/routes/schedule.js`), the owner ranks this feature among the worker-app priorities, and iOS is the only worker surface that cannot show it. The route already exists and needs no change: it answers the SESSION's worker only (a `?worker_id=` is ignored), uncancelled `planned_shifts` with `ends_at > now()` and `starts_at < now() + 31 days`, in start order, at most 200, tenant-scoped by RLS.

The risk this decision exists to bound is the one the planning table was designed against: `planned_shifts` "never write to shifts or affect NFC eligibility or payroll" (migration 025). A worker app that LISTS plans is only safe while the list stays a picture and never becomes an input.

## Decision

1. The iOS worker app shows the signed-in worker's planned assignments, READ-ONLY, from `GET /me/schedule`. Android's behaviour at 60f6886 is the reference, ported clause for clause.
2. DISPLAY ONLY. A plan is never read by tap handling, `syncPending`, `refresh()`, the shift signals (badge, reminders, Live Activity), navigation or the tab lock. `planned_shifts` never join payroll, the P&L or NFC eligibility. A failing, slow or absent schedule must never delay or fail a clock-in; the schedule load is its own unstructured task, concurrent with and never inside the roster / sync pass.
3. Two surfaces and nothing else: a collapsed "Next planned assignment" row (View / Close) on the idle list and on the running screen, which expands into a "My schedule" card (first assignment; "All upcoming assignments" lists them all). No new tab, no push, no reminder, no deep link from an assignment into a clock-in.
4. Identity comes from the session (the `ts_worker` cookie), never from a field the phone fills in (decision-22). The request carries no worker id, goes through the worker's `apiGet`, and never through `OperatorAPI`.
5. The schedule is held IN MEMORY only (never SwiftData, never UserDefaults, never cached across launches or covered by decision-62), fetched fresh on every shift-screen appearance and every return to the foreground, and invalidated by sign-out, a 401 and a change of worker. A superseded or cancelled request never publishes, and the previous list is dropped while a new one loads.
6. Dates and times are rendered in Europe/Vienna, whatever zone the phone is set to (the same rule as the admin week board and Android's My hours). Same Vienna day: "<date> · <from>-<to>"; otherwise "<date>, <from> - <date>, <to>". Medium date, short time, in the phone's locale.
7. Failure is told only where the worker asked for the schedule. The collapsed row shows NOTHING under it while loading, failed or empty; the expanded card says "could not load" (offline vs. other) with a Try again control, or "no assignments in the next 31 days". A 401 renders nothing (the app signs out). A server that predates migration 025 answers 404 / 500 and reads as the generic failure inside the expanded card only.
8. Copy takes Android's German verbatim (formal "Sie"); an assignment is an "Einsatz" (the plan), never a "Schicht" (what was recorded).

## Consequences

- `docs/product-launch-and-scheduling.md` line 36 is amended by this decision, and the sentence there now points here: iOS shows the worker's plan; it still does not plan, remind or change NFC behaviour.
- No server change and no new endpoint.
- If production has not deployed migration 025, every launch of the iOS app yields the generic error, but only inside the expanded card; the collapsed row hides it by design (as Android does), so the worker's idle and running screens look unchanged.
- The Blue Hour reskin (B1-B5) restyles the three views of this feature (`ScheduleSummary`, `ScheduleCard`, `ScheduleAssignmentRow`), which are built without any surface of their own for that reason.
- Out of scope, deliberately: a calendar view, a reminder before an assignment, deep-linking an assignment to a tag scan, an "in progress" badge, grouping by day, and the dead Android `schedule_explainer` string.
