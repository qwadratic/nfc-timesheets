---
id: decision-82
title: >-
  iOS says what the phone still holds and what the server has not confirmed -
  device-wide count rows and a details sheet in words that never promise
  automatic delivery (ports Android TASK-339/363 with iOS wording, no schema
  change)
date: '2026-10-12 10:20'
status: accepted
---
## Context

(TASK-365.7, iOS P6. The parity plan called this decision-79/80; 77 and 78 went to branch admin-declutter, 79 to the agent-integration decision and 81 to manual start, so it is the next free number.)

Android (PRs 3-7, 60f6886: TASK-225, TASK-339, TASK-363) keeps unsent and blocked shifts visible as two compact, tappable count rows - on the idle list, on the running screen and on the SIGN-IN screen - and opens a details sheet with a state-specific explanation, the earliest start and the last attempt. Its acceptance criterion 3 is "no false automatic-delivery promise".

iOS has no summary of unsent work on any screen. A row's own "Sending..." / error label lives in Recent and History, which are invisible while a shift runs and after sign-out; the only mention is a Settings footer read BEFORE signing out. A worker who signs out with unsent shifts, or who finishes a shift in a basement, has no sign that the phone still holds hours the server has not confirmed.

iOS differs from Android in three ways that make a verbatim port wrong:

1. There is NO background delivery (Sync.swift: "no background retry", BGAppRefreshTask is not adopted). Android's `delivery_automatic` ("Your phone will try again automatically when a connection is available") and its force-stop note would be false promises here.
2. The row is written BEFORE the POST, so a start is unacknowledged for one request on every normal tap (P5's two-second grace) and "waiting" must never flash for it.
3. There is no per-row last-attempt field, and adding a SwiftData column is not free: a failed lightweight migration is a `fatalError` at launch (NFCTimeSheetsApp.swift), for one line of text.

origin/main's shift-evidence feature adds two shapes the count has to read correctly: a close the server refused with 422 `proof_required` REOPENS the row (open again, not blocked), and a finish that carries a proof is owed to the server while the row is still open locally (`pendingEvidenceEnd`).

## Decision

1. PRESENTATION ONLY. The rows and the sheet read the store; nothing reads them. They never stop the clock, hide or disable a control, change `ShiftSignal.plan`, gate, delay or alter a tap, a sync pass or an accounting figure, and a failing summary can only cost a line of text. They delete nothing, and closing the sheet deletes nothing.
2. WHAT COUNTS - one predicate, structurally shared with the push. `PendingWork.state(of:)` (Foundation-only) is the ONLY definition: DELIVERED = the server has the open and (the shift is still open, or it has the close) and no finish is owed with a proof; BLOCKED = not delivered and `syncBlocked` (a terminal refusal, or queued under another account); WAITING = not delivered and not blocked. `syncPending` iterates exactly the WAITING rows, so what the engine will try and what the screen counts cannot disagree. An open shift whose OPEN landed is not pending - including one a 422 `proof_required` reopened. A finish owed with a proof is WAITING. A WAITING row whose last local write (its finish, else its start) is younger than `PendingNotice.grace` (2 s) is a request in flight, not a delivery problem, and is held back from the screens (`PendingWork.settled`, woken by one display-only task in LogView) - so a normal online clock-in or clock-out never pops a row in and out, and the row and P5's "Not confirmed yet" heading appear at the same moment. A BLOCKED row is never held back, and neither is an old one.
3. DEVICE-WIDE. The counts cover every account's rows (the phone is the outbox, decision-22 / WorkerScope), read ONLY through `WorkerScope` (`deviceWide()`); lists, totals, the tab lock and every tap stay scoped to the signed-in worker. Nothing is deleted on sign-out, so the SIGN-IN screen shows the same device-wide counts with the same sheet. BLOCKED and WAITING are separate rows (blocked first, in the error colour AND in words), because "wait for a signal" and "phone the office" are opposite instructions.
4. WORDS THAT ARE TRUE ON iOS. The sheet says what the phone holds and what the server has not confirmed, and that opening the app (or pulling to refresh) tries again. Exactly one sentence per waiting state: signed out, or every waiting row belongs to another account -> "Sign in with the same account so these entries can be delivered."; otherwise -> "Automatic delivery is not currently active. Open the app with an internet connection to try delivery again." Blocked: the office must review these entries, they stay on this phone and are not sent again, and the worker is to tell the office the time shown below. NO sentence promises automatic delivery, a background retry or a retry on a schedule; Android's `delivery_automatic`, `pending_force_stop_note` and the `pushArmed` input are NOT ported. German is Android's (formal Sie, "Objekt", never "Gebäude"); the one deliberate wording change is the blocked detail, which drops Android's "will not retry automatically" / "nicht automatisch erneut gesendet" for "are not sent again" / "nicht erneut gesendet", so that no string on this surface contains the word "automatically" at all.
5. LAST ATTEMPT WITHOUT A SCHEMA CHANGE. One `UserDefaults` date, stamped immediately BEFORE each request the sync pass (or the proof-close) makes for a row - Android's markAttempted-before-call. It is a single global value, not a per-row maximum (documented deviation), and it is shown only when it is not earlier than the earliest unsent start (an attempt that predates the row cannot have been about it); otherwise the sheet says "No delivery attempt yet." `Shift` is not touched.
6. SURFACES. `DeliveryStatusRows` and `DeliveryDetailsSheet` bring no surface of their own (no background, card or fixed colour but the red of a blocked row); the List, the running screen and the sign-in Form supply the container, so the Blue Hour reskin (B1-B5) restyles those, not these views. Placement: idle list right after the unresolved banner; running screen after the resolver card; sign-in screen between the brand block and the code form.

## Consequences

- A worker who finishes in a basement, signs out, or hands the phone to a colleague sees what the phone still holds, on every screen they can reach, in words that are true on this platform.
- An offline tap shows its waiting row after two seconds, not at once; the moment is fixed by the row's own timestamps, so a reopened app shows an old unsent row immediately.
- The idle list and the sign-in form render nothing at all when the outbox is empty (no empty section, no gap), and the details sheet closes by itself when the last row is delivered.
- `syncPending`'s row filter changes spelling but not meaning (`!syncBlocked && (!isFullySynced || pendingEvidenceEnd != nil)` became `PendingWork.state(of:) == .waiting`); checks/pending-work-check.swift proves the equivalence over every combination of the inputs and pins the call.
- "Last attempt" is global, so after a successful delivery it can show a time that belongs to a different row; the guard in (5) keeps it from predating the row it is shown for. A per-row value would need a SwiftData column and is deferred until the store has a migration plan.
- Rows queued under ANOTHER account whose open already landed are WAITING (nobody blocks them: P3's pushClose skip) and are delivered when that account signs back in; the sheet says so only when ALL waiting rows are such rows. In a mix, the "open the app" sentence stays, because it is true for the signed-in worker's own rows.
- The Settings footer ("Anything still waiting to send will be blocked until you sign back in") is unchanged.
