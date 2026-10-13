---
id: decision-83
title: >-
  iOS shows a finished-shift receipt, plays a one-shot confirmation only after a
  clean server acknowledgement, and gets the read-only My hours list - ports
  Android TASK-363/TASK-189 at 60f6886, presentation only, no new endpoint
date: '2026-10-12 10:53'
status: accepted
---
## Context

(TASK-365.8, iOS P7. The parity plan called this decision-78/79/80; 77 and 78 went to branch admin-declutter, 79 to the agent-integration decision, 80 to the schedule, 81 to manual start and 82 to delivery status, so it is the next free number. It is also the "decision-80 proposal" the plan's OD4 asked for: My hours is a pre-range gap, TASK-189 - planned as accepted and detachable.)

Android at 60f6886 (TASK-363, docs/ANDROID-WORKER-DESIGN.md "Confirmation motion" and "Final composition"; TASK-189, since 2026-08-24):

- After a finish, the idle screen replaces the start card with a "Schicht beendet" receipt - site, start-end, duration, correction state, one delivery line - that is offered when the newest closed shift ended 0-120 s ago and then stays until the worker presses Weiter.
- A one-shot 900 ms ring-then-check plays only after a clean server ACK of a clock-in or a clock-out, for an event at most 45 s old, once per identity, with the identity written to a presentation-only preference BEFORE the motion; Android's animator scale 0 shows the stable state.
- More > "Meine Stunden" lists the worker's last 60 days as the SERVER has them (GET /shifts/mine?since=now-60d on every entry, never cached), so an admin correction or a shift from another device is visible.

iOS had none of the three: a finish dropped straight to the list, the clock card looked the same before and after the server accepted, and History shows local rows only. `ShiftAPI.mine(since:)` existed but was called only by the on-device migration.

iOS differs from Android in ways that make a verbatim port wrong:

1. The row is written BEFORE the POST (P5/P6). Every online clock-out is "not delivered" for one request, so a receipt that said "Saved on this phone - not yet confirmed" at once would flash a warning on every normal stop (the same problem P5's 2 s grace and P6's `settleGrace` solve).
2. There is no background delivery, so no sentence the receipt adds may promise one.
3. On iOS the idle list is Recent first and the scan / manual-start Sections below it, so "replace the start card" has no single place; the receipt goes at the top and the two start Sections are hidden while it is up.
4. The server echoes a finish time back truncated to milliseconds (`apply()` overwrites `endTime` with it), so a receipt identity built from the raw `Date` would change when the ACK lands.
5. `@Query` republishes on SwiftData's schedule and the running screen sits in a once-a-minute `TimelineView`, so the motion must read the flip from the row's own facts and keep its animation clock in a child that survives the tick.

The server contract is unchanged and was read, not assumed: `GET /shifts/mine?since=<iso8601>` (server/routes/app.js `myShifts`, `auth: "worker"`) -> `200 {shifts:[...]}` for the SESSION's worker only, newest `start_time` first, at most 500 rows, each row the shift columns plus `location_slug`, `location_name` (the BUILDING: a shift stores `place.location_id`) and `zone_name`. `since` is required: `400 invalid_field` when missing, `400 invalid_timestamp` when unparseable, `422 timestamp_out_of_range` / `timestamp_in_future` when outside the validator's window; `401 unauthorized` (no or lapsed `ts_worker`, a deactivated worker, or a wrong app key). There is no `?worker=` and there must never be one (decision-22).

## Decision

1. PRESENTATION ONLY. The receipt, the motion and My hours never gate, delay or alter a tap, a sync pass, an accounting figure or navigation, and nothing in them writes a shift, deletes a row or reads the device-wide outbox. The pure files are Foundation-only and check-covered; the views draw from values. `handleTap`, `finishManualStop`, `prepareCompletion`, `refresh()` and the sync engine do not mention any of them (checks/shift-receipt-check.swift, worker-motion-check.swift and my-hours-check.swift read the sources as text), and the "tap is never blocked" ordering pinned by checks/shift-signal-check.swift is untouched. The one thing a receipt hides is the in-app "Scan a tag" / "Start without a tag" pair, for as long as the receipt is up - exactly as Android's receipt replaces its start card. A background tag tap is unaffected and Continue is one tap away.

2. THE RECEIPT. The row is the signed-in worker's newest finished row (`recent.first`, WorkerScope `completed(for:)`). It is OFFERED when its finish is 0-120 whole seconds old at the moment it is first seen (Android's `Duration.between(end, now).seconds in 0..120`, floored, so a finish in the future is never offered); the offer is CAPTURED once into the screen's @State and then stays until Continue, even after the 120 s window; the DISMISSED identity is kept in @State and never re-offers; a different finished row (another client_uuid, or a finish time that differs by a second or more) is a new offer. The identity is client_uuid plus finish time, compared with a 1 s tolerance because of (4) above. Relaunching after the window shows nothing. The receipt is inline in the list - a Section after the unresolved banner and before the delivery rows - never a sheet or alert, so taps, tabs, the resolver banner and the resolver sheet keep working, and its row is filtered out of Recent meanwhile.

3. THE DELIVERY LINE says the DELIVERY FACT, from the one predicate P6 defined (`PendingWork.state`): the row's recorded problem sentence (with the red icon when nobody is retrying it) / "Sent" / "Saved on this phone · not yet confirmed", plus "Sending..." for a request still inside the 2 s grace. Two deliberate differences from Android's line: (a) the in-flight state (Context 1); (b) a delivered row that still needs its finish time resolved says "Sent" beside the red "Auto-closed" pill - Android prints "Saved on this phone" there only because it reuses the motion's `confirmed` flag, which is false for a row that needs resolution, and iOS keeps "what the server has" (this line) and "may the check play" (the motion) as two separate questions. A finished-but-unsent shift therefore shows its delivery state in the receipt and never a check.

4. THE MOTION (ConfirmationMotion.swift, ConfirmationMark.swift). It plays only after a CLEAN ACK: for the clock-in, `ShiftSignal.isConfirmed` (the open was acknowledged, no error, not overdue); for the clock-out, the row is delivered, carries no error and does not need resolution. The gate is `shouldPlay(identity, confirmed, eventTime, now, lastConsumed)`: confirmed AND whole seconds since the event in 0...45 (Android's `age in 0..45`) AND the identity is not the last one consumed for that kind. The identity ('locationId:startMillis' for a clock-in, 'clientUuid:endMillis' for a clock-out) is written to UserDefaults BEFORE anything animates - for every confirmed, unconsumed identity, including a late one that does not play, and also under Reduce Motion, which shows the stable state. Clock-in and clock-out are two independent keys. A pending, failed or blocked state is never confirmed, so it neither plays nor consumes. The trigger is `.onChange(of: identity + confirmed, initial: true)`, the same keying as Android's `LaunchedEffect(identity, confirmed)`: a restored or adopted old shift is excluded by the 45 s window, a queued one by `confirmed == false`. The stages are Android's on a linear 0.9 s clock: ring 0-0.48, check 0.43-0.63, exit 0.67-0.80, content 0.80-1.00. The ink is the primary label colour - never green (decision-60). The mark is `accessibilityHidden`; the time and its accessibility label exist throughout; nothing waits on it and it writes nothing.

5. MY HOURS (MyHours.swift, MyHoursView.swift). One new row in Settings, "My hours", pushes a screen that calls `ShiftAPI.mine(since: now - 60 days)` on EVERY entry through the `LoadGuard` P4 built: a newer request, a worker change, a sign-out or a cancel drops the answer, so B never sees A's list, and nothing is cached. States: loading / failed (the offline sentence only for status 0, else the generic one, both with "Refresh") / loaded (the empty sentence, or the rows); a 401 reads as nothing (the session choke point is already signing out). Rows: building (`location_name`, else "Unknown location"), the status word in Android's order - no end time -> "In progress", needs resolution -> "Auto-closed", corrected -> "Corrected", else "Closed" - the iOS "Manual" pill, date, start, end or "No end yet", and the duration for a finished row only, all in Europe/Vienna through P4's `ViennaTime`. No total, no rate, no write control, no cache. The wire decode is strict like the migration's: one unreadable row is the generic error, never a silently shorter list of somebody's hours.

6. SURFACES AND WORDS. The new views bring no surface of their own (no background, card, corner radius or fixed colour: they use the shared `pill` and semantic colours), so the Blue Hour reskin (B1-B5) restyles the containers they sit in. Both languages ship with the code: English sentence = key, German verbatim from Android 60f6886's strings.xml (formal Sie, "Objekt").

## Consequences

- A worker who finishes a shift sees the receipt at once with one honest line about delivery, and the check only when the server has said yes; an offline or refused finish shows the row's own sentence in the same place and no motion.
- The receipt and the clock-in motion read the same SwiftData row as every other screen, so they cannot disagree with the sync engine; no new store, schema column or endpoint exists.
- Android's rememberSaveable also survives a system-killed-process restore, which the iOS @State does not: the receipt is then re-offered only if its finish is still under two minutes old.
- Hiding the two start controls while the receipt is up costs one extra tap (Continue) for an in-app scan right after a finish. The first frame after a finish shows the receipt, not the start controls (the offer is derived in the same render, then captured).
- The "Manual" pill appears on the receipt and in My hours (decision-56 section 5: every list that shows shifts must show it), which Android's receipt does not need.
- My hours is detachable: two files and one Settings row. Dropping it touches nothing else.
- The motion's UserDefaults keys are presentation memory only; clearing them replays at most one check, and only for a clean ACK of an event under 45 s old.
- Not verified without a worker session on a device or simulator (TASK-365.22 is that rig): the look and timing of the ring-then-check, VoiceOver order, Reduce Motion in the real setting, and My hours against a real server. The rule behind each is pinned by a runnable check.
