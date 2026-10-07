// Runnable check: the in-shift state machine. No test framework, no Xcode, no simulator.
//
//   cd NFCTimeSheets
//   cat NFCTimeSheets/ShiftSignal.swift checks/shift-signal-check.swift \
//     > /tmp/shift-signal-check.swift && swift /tmp/shift-signal-check.swift
//
// Five things are pinned here, and every one of them is a way this feature could quietly
// cost somebody money (the fifth - section 7 - is TASK-365.6: "Not confirmed yet" is WORDS and
// never behaviour):
//
//   1. THE STATE MACHINE. A shift opens -> the lock, the badge, the ladder and the Live
//      Activity are on. It closes -> every one of them is off. Past 8h -> the clock stops
//      being a running clock, because the server has already closed that row.
//   2. THE LOCK NEVER TRAPS ANYBODY. Materials and Settings are in visibleTabs in EVERY
//      state, so sign-out (decision-22) and asking for supplies stay reachable.
//   3. THE PERMISSION PROMPT IS NEVER ON THE TAP PATH. Not before the first clock-in,
//      not twice.
//   4. THE TAP IS NEVER BLOCKED BY A SIGNAL. Read out of ContentView.swift as text,
//      because that ordering lives in SwiftUI code this runner cannot import: the local
//      row is written and SAVED before arm(for:) is called, and arm() is not awaited.
//      A cache miss is not a rejection - that bug already cost this project a dead tap.
//   5. "NOT CONFIRMED YET" IS WORDS (TASK-365.6). A start only the phone knows about changes
//      the screen's heading, the word under the clock and the ladder's text - and not one bit
//      of the plan: lock, badge, rung timing and the 8h phase are equal for a pending and a
//      confirmed shift. The ladder is re-armed after the push so the text flips on acceptance.
//
// Mirrored by android/checks/core-check.kt section 13. The two platforms are supposed to
// behave the same; if one of these files changes alone, that has stopped being true.

import Foundation

func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        exit(1)
    }
}

let start = Date(timeIntervalSince1970: 1_700_000_000)   // fixed, so nothing depends on "now"
func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

let shift = RunningShift(locationId: "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
                         locationName: "Westbahnhof",
                         startTime: start)

// ---------------------------------------------------------------------------------
// 1. The state machine
// ---------------------------------------------------------------------------------

// A shift opens: everything on.
let opened = ShiftSignal.plan(for: shift, now: at(0.01))
check(opened.lockScreen, "an open shift puts the app into the locked shift screen")
check(opened.badgeCount == 1, "an open shift owns the app-icon badge")
check(opened.remindersScheduled, "an open shift schedules the reminder ladder")
check(opened.liveActivity, "an open shift asks for a Live Activity")
check(opened.phase == .running, "and it is running")

// A shift closes: everything off. This is the invariant that stops a closed shift
// leaving a badge on the home screen and a Live Activity on the Lock Screen.
let closed = ShiftSignal.plan(for: nil, now: at(3))
check(closed == ShiftSignal.SignalPlan.idle, "no open shift means the idle plan and nothing else")
check(!closed.lockScreen, "a closed shift unlocks the app")
check(closed.badgeCount == 0, "a closed shift clears the app-icon badge")
check(!closed.remindersScheduled, "a closed shift cancels the ladder")
check(!closed.liveActivity, "a closed shift ends the Live Activity")
check(closed.phase == nil, "a closed shift has no phase")

// The 8h boundary, computed LOCALLY. ops/sql/autoclose.sql closes at start+8h and the
// client must reach the same conclusion with no server round trip, because a clock-in
// works offline.
check(ShiftSignal.autoCloseAfter == 8 * 3600, "the auto-close boundary is 8 hours (decision-10)")
check(ShiftSignal.phase(startTime: start, now: at(7.99), serverAutoClosed: false) == .running,
      "7h59 is still running")
check(ShiftSignal.phase(startTime: start, now: at(8.0), serverAutoClosed: false) == .overdue,
      "exactly 8h is overdue - the server's timer has fired by then")
check(ShiftSignal.phase(startTime: start, now: at(8.01), serverAutoClosed: false) == .overdue,
      "8h01 is overdue")
check(ShiftSignal.autoCloseDeadline(after: start) == at(8), "the deadline is start + 8h")

// Past 8h: still locked, still badged, but no running clock and no new pings about a
// shift the server has already closed.
let overdue = ShiftSignal.plan(for: shift, now: at(9))
check(overdue.phase == .overdue, "past 8h the phase flips")
check(overdue.lockScreen, "...the screen stays - the worker still has to act")
check(overdue.badgeCount == 1, "...and so does the badge")
check(!overdue.remindersScheduled, "...but nothing new is scheduled: every rung has fired")
check(!overdue.liveActivity,
      "...and no Live Activity is requested past 8h - ActivityKit hard-ends it there anyway")

// THE AUTO-CLOSED SHIFT MUST NOT LEAVE A STUCK LOCK. Two halves, and both are needed.
// Half one: the server says auto_closed while the local row is still open. The clock
// stops being a running clock immediately, whatever the wall time says.
let serverClosed = RunningShift(locationId: shift.locationId, locationName: shift.locationName,
                                startTime: start, serverAutoClosed: true)
check(ShiftSignal.phase(of: serverClosed, now: at(0.5)) == .overdue,
      "a server-flagged auto-close is overdue after 30 minutes, not after 8 hours")
let flagged = ShiftSignal.plan(for: serverClosed, now: at(0.5))
check(!flagged.liveActivity && !flagged.remindersScheduled,
      "a shift the server has closed never shows a running timer or schedules a reminder")
// Half two: the worker confirms the finish time, the row closes, arm(for: nil) runs, and
// there is nothing left anywhere. Same value as a normal tap-out - one code path.
check(ShiftSignal.plan(for: nil, now: at(9)) == ShiftSignal.SignalPlan.idle,
      "resolving an auto-closed shift leaves no lock, no badge, no notification")

// ---------------------------------------------------------------------------------
// 2. The lock never traps anybody
// ---------------------------------------------------------------------------------

for running in [true, false] {
    let tabs = ShiftSignal.visibleTabs(shiftRunning: running)
    check(tabs.contains(.log), "the log tab exists whether or not a shift runs (\(running))")
    check(tabs.contains(.materials),
          "materials is reachable while a shift runs - that is exactly when it is needed (\(running))")
    check(tabs.contains(.settings),
          "settings, and therefore SIGN OUT, is reachable in every state (decision-22) (\(running))")
    check(!tabs.isEmpty, "there is always something to tap")
}
check(!ShiftSignal.visibleTabs(shiftRunning: true).contains(.history),
      "history is the one thing the lock hides - nothing in it is time-critical")
check(ShiftSignal.visibleTabs(shiftRunning: false) == AppTab.allCases,
      "with no shift running the app is exactly as it was")

// ---------------------------------------------------------------------------------
// 3. The permission prompt
// ---------------------------------------------------------------------------------

check(!ShiftSignal.shouldAskForNotifications(hasClockedIn: false, alreadyAsked: false),
      "NEVER ask before the first clock-in: that means asking at a door at 06:02 with gloves on")
check(ShiftSignal.shouldAskForNotifications(hasClockedIn: true, alreadyAsked: false),
      "ask once, afterwards, from the shift screen")
check(!ShiftSignal.shouldAskForNotifications(hasClockedIn: true, alreadyAsked: true),
      "and never again - a refusal is one sentence, not a nag")

// ---------------------------------------------------------------------------------
// 4. The ladder
// ---------------------------------------------------------------------------------

check(ShiftSignal.reminderHours == [1, 2, 3, 4, 5, 6, 7, 8], "eight rungs, one an hour")
check(ShiftSignal.reminderHours.count < 64,
      "well under the system's 'soonest-firing 64 notifications' ceiling")
check(!ShiftSignal.isAutoCloseWarning(hour: 7), "the 7h rung is a nudge")
check(ShiftSignal.isAutoCloseWarning(hour: 8),
      "the 8h rung is the auto-close itself and says something different")
check(ShiftSignal.reminderHours.allSatisfy { TimeInterval($0) * 3600 <= ShiftSignal.autoCloseAfter },
      "no rung fires after the server has closed the shift")

// ---------------------------------------------------------------------------------
// 5. Spoken duration - one label, not a per-second live region
// ---------------------------------------------------------------------------------

let spoken = ShiftSignal.elapsed(from: start, to: at(3) + 14 * 60 + 30)
check(spoken.hours == 3 && spoken.minutes == 14,
      "3h14m30s is spoken as 3 hours 14 minutes: the seconds are deliberately not in it")
let sameMinute = ShiftSignal.elapsed(from: start, to: at(3) + 14 * 60 + 59)
check(spoken == sameMinute,
      "the spoken label does not change within a minute, so VoiceOver is not spammed")
check(ShiftSignal.elapsed(from: start, to: start.addingTimeInterval(-60)) == (0, 0),
      "a phone whose clock jumped backwards reads 0h 0m, never a negative duration")

// ---------------------------------------------------------------------------------
// 6. THE TAP IS NEVER BLOCKED (audit R2), read out of ContentView.swift as text
// ---------------------------------------------------------------------------------
//
// This is the one check that must exist. The rest of this file proves the state machine
// is right; this proves it is armed from a place where it cannot cost anybody a clock-in.

let view = try! String(contentsOfFile: "NFCTimeSheets/ContentView.swift", encoding: .utf8)
let handleTap = view.components(separatedBy: "private func handleTap(")[1]
    .components(separatedBy: "private func outcome(")[0]

let save = handleTap.range(of: "try? context.save()")
let arm = handleTap.range(of: "signals.arm(")
check(save != nil, "handleTap still saves the local row")
check(arm != nil, "handleTap arms the signal")
check(save!.upperBound < arm!.lowerBound,
      "THE LOCAL ROW IS SAVED BEFORE ANY SIGNAL WORK. A tap in a basement counts even if "
      + "every signal fails; the reverse would lose paid time.")
check(!handleTap.contains("await signals."),
      "no signal call is awaited on the tap path - arm() is synchronous and non-throwing")
check(!handleTap.contains("requestAuthorization"),
      "the notification prompt is NEVER on the tap path (audit R3)")
check(!handleTap.contains("try await") || handleTap.range(of: "try await")!.lowerBound > save!.upperBound,
      "nothing that can throw runs before the row is saved")

// THE ROSTER REFRESH AFTER A TAP (decision-43). A zone created after the last roster fetch is
// unknown until the next one, so the tap path refreshes it - as its OWN un-awaited Task, after
// the save and after the arm, so a dead network can never delay or fail a clock-in.
let refreshTask = handleTap.range(of: "await refreshRoster(context: context)")
check(refreshTask != nil, "handleTap refreshes the roster after a tap so a brand-new zone gets its building name")
check(refreshTask!.lowerBound > arm!.upperBound,
      "the roster refresh comes AFTER the signal is armed and the row is saved, never before")
let beforeRefresh = String(handleTap[..<refreshTask!.lowerBound])
check(beforeRefresh.components(separatedBy: "Task {").count - 1 >= 1 && beforeRefresh.hasSuffix("") ,
      "the refresh sits inside its own Task")
check(!handleTap.contains("try await refreshRoster"), "the refresh is not on a throwing path")

// SAME BUILDING, NOT SAME ID (decision-43): tapping out at a building's second zone must close
// the shift, not auto-close it as a walk-away and open a new one.
check(handleTap.contains("Zones.buildingIdOf(running.locationId, zones: rosterZones.zones)"),
      "the tap compares the running shift's BUILDING, not its raw place id")
check(!handleTap.contains("running.locationId != locationId"),
      "...and the raw-id comparison that turned a second door into a switch is gone")

// The foreground handler refreshes too: the app is the only place a zone created while it was
// away can be learned, and it must re-arm so fixed-text reminders carry the real name.
let foreground = view.components(separatedBy: ".onChange(of: scenePhase)").last!   // the LogView one: the outer view has its own
    .components(separatedBy: "\n        }\n    }")[0]
check(foreground.contains("await refreshRoster(context: context)") && foreground.contains("signals.arm("),
      "coming back to the foreground refreshes the roster and re-arms")

// MATERIALS: the server validates a request's building against BUILDINGS only, so the context
// must come from Zones.materialContext, never straight off the shift's (zone) place id.
let materialsView = try! String(contentsOfFile: "NFCTimeSheets/MaterialsView.swift", encoding: .utf8)
check(materialsView.contains("rosterZones.materialContext(of:"),
      "a material request's building is resolved through Zones.materialContext")
check(!materialsView.contains("private var contextLocationId: String? { openShift?.locationId }"),
      "...and the old line that sent the zone id (a guaranteed 422) is gone")

// The recovery half of the same wire: adopting a shift the server knows about and this
// phone does not must arm exactly like a fresh tap does (audit §4).
let refresh = view.components(separatedBy: "private func refresh() async {")[1]
    .components(separatedBy: "\n    }")[0]
check(refresh.contains("adoptServerOpenShift"), "refresh still adopts the server's open shift")
check(refresh.contains("armIfStillCurrent()"),
      "...and re-arms from it, so a reinstalled or rebooted phone gets its signal back")
// TASK-365.4. The re-arm after five awaits is the GUARDED one: a refresh that started for worker A
// and lands after A signed out (Session's teardown already ran) or after B replaced A must not put
// A's badge back. The guard is a pure rule (WorkerScope.isCurrent) asked of the live session.
let armIfCurrent = view.components(separatedBy: "private func armIfStillCurrent() {")[1]
    .components(separatedBy: "\n    }")[0]
check(armIfCurrent.contains("WorkerScope.isCurrent(worker.id, session: session.worker?.id)"),
      "the re-arm after an await asks whether this worker STILL holds the session")
check(armIfCurrent.contains("signals.arm(for: currentRunning())"),
      "...and then arms through the same one wire as the tap path")
check(handleTap.contains("armIfStillCurrent()"),
      "handleTap's post-roster re-arm is the guarded one (the synchronous arm right after the save is not gated)")

// SCOPED TO THE SIGNED-IN WORKER (TASK-365.4). On a shared phone worker A's leftover open row is
// still in the store; arming worker B's badge, ladder and Live Activity from it would tell B they
// are clocked in at A's building. What the signals are armed FROM reads the session worker's row only.
let currentRunning = view.components(separatedBy: "private func currentRunning() -> RunningShift? {")[1]
    .components(separatedBy: "\n    }")[0]
check(currentRunning.contains("openShift(for: worker.id)"),
      "currentRunning() - the value every out-of-app signal is armed from - filters by the session's worker id")
check(!currentRunning.contains("first(where: \\.isOpen)"),
      "...and the unscoped first(where: \\.isOpen) is gone from it")

// TEARDOWN TAKES BACK WHAT WAS ALREADY DELIVERED, not just what is still scheduled.
// A shift that closed at 07:40 leaving the 07:00 "Still clocked in" banner in Notification
// Center is worse than no signal at all: it tells somebody who has finished that they have
// not. Android cancels its delivered reminder by id; this is the iOS half.
let center = try! String(contentsOfFile: "NFCTimeSheets/ShiftSignalCenter.swift", encoding: .utf8)
check(center.contains("removePendingNotificationRequests(withIdentifiers: Self.allReminderIds)"),
      "tearing down cancels the scheduled rungs")
check(center.contains("removeDeliveredNotifications(withIdentifiers: Self.allReminderIds)"),
      "...AND removes the rungs already sitting in Notification Center - a stale "
      + "'you are still working' notification is worse than none")

// SIGNING OUT TEARS EVERY SIGNAL DOWN (TASK-365.4). Mirrors android/checks/core-check.kt: "signing
// out tears every signal down". Session.clearLocalSession is the ONE teardown both exits share -
// a deliberate sign-out and the 401 path (serverRejectedSession) - so a phone handed to a colleague
// stops showing a badge, +1h..+8h reminders and a Live Activity for a shift nobody is signed in to.
// arm(for:) is otherwise reachable only from LogView, which is unmounted by then.
let auth = try! String(contentsOfFile: "NFCTimeSheets/Auth.swift", encoding: .utf8)
let clearLocal = auth.components(separatedBy: "private func clearLocalSession() {")[1]
    .components(separatedBy: "\n    }")[0]
check(clearLocal.components(separatedBy: "\n").contains { l in
          !l.trimmingCharacters(in: .whitespaces).hasPrefix("//") && l.contains("ShiftSignalCenter.shared.arm(for: nil)")
      },
      "signing out tears every signal down: clearLocalSession calls ShiftSignalCenter.shared.arm(for: nil)")
check(auth.components(separatedBy: "clearLocalSession()").count - 1 >= 3,
      "...and both signOut and serverRejectedSession go through it (declaration + two callers)")
check(ShiftSignal.plan(for: nil, now: at(3)) == ShiftSignal.SignalPlan.idle &&
      ShiftSignal.plan(for: nil, now: at(3)).badgeCount == 0,
      "arm(for: nil) is the idle plan: badge 0, no ladder, no Live Activity")

// The badge has ONE owner. Two writers would fight over a surface that carries one number.
let materials = try! String(contentsOfFile: "NFCTimeSheets/MaterialStore.swift", encoding: .utf8)
check(!materials.contains("setBadgeCount"),
      "materials never touch the APP-ICON badge - the open shift owns it (the tab badge is a different surface)")

// ---------------------------------------------------------------------------------
// 7. "NOT CONFIRMED YET" IS WORDS, NEVER BEHAVIOUR (TASK-365.6, iOS P5)
// ---------------------------------------------------------------------------------
//
// A start that exists only on the phone is SAID so - the running screen's heading, the word under
// the clock, what VoiceOver reads, the one-line notice, and every reminder's text. It must never
// GATE anything: the plan, the lock, the badge, the ladder's timing and the 8h phase are the same
// value for a pending shift as for a confirmed one. Mirrors android/checks/core-check.kt's pending
// section and Android 60f6886 (RunningShift.pendingConfirmation, TimeSheetApp.kt, ShiftSignals.kt).

let pendingShift = RunningShift(locationId: shift.locationId, locationName: shift.locationName,
                                startTime: start, pendingConfirmation: true)
check(!shift.pendingConfirmation && !serverClosed.pendingConfirmation,
      "the flag defaults to false, so every existing RunningShift(...) call keeps its meaning")
check(pendingShift.pendingConfirmation && pendingShift != shift,
      "the flag is part of the value (Equatable): an acknowledgement is a change the arm can see")

// plan(pending) == plan(not pending): lock, badge, reminders, Live Activity, phase - at every
// instant that matters and with or without the server's auto-close flag.
for hours in [0.0, 0.01, 0.99, 1.0, 3.0, 7.99, 8.0, 8.01, 9.0, 24.0] {
    for auto in [false, true] {
        let confirmedValue = RunningShift(locationId: shift.locationId, locationName: shift.locationName,
                                          startTime: start, serverAutoClosed: auto, pendingConfirmation: false)
        let pendingValue = RunningShift(locationId: shift.locationId, locationName: shift.locationName,
                                        startTime: start, serverAutoClosed: auto, pendingConfirmation: true)
        check(ShiftSignal.plan(for: pendingValue, now: at(hours)) == ShiftSignal.plan(for: confirmedValue, now: at(hours)),
              "a pending shift has the SAME plan as a confirmed one (+\(hours)h, serverAutoClosed \(auto)): "
              + "the flag chooses words, it never gates the lock, the badge, the ladder or the Live Activity")
        check(ShiftSignal.phase(of: pendingValue, now: at(hours)) == ShiftSignal.phase(of: confirmedValue, now: at(hours)),
              "...and the same 8h phase (+\(hours)h)")
    }
}
let pendingPlan = ShiftSignal.plan(for: pendingShift, now: at(0.01))
check(pendingPlan.lockScreen && pendingPlan.badgeCount == 1 && pendingPlan.remindersScheduled
      && pendingPlan.liveActivity && pendingPlan.phase == .running,
      "a start that only the phone knows about still locks the screen, owns the badge and arms the ladder")
check(ShiftSignal.autoCloseAfter == 8 * 3600 && ShiftSignal.reminderHours == [1, 2, 3, 4, 5, 6, 7, 8],
      "the flag did not touch the shared constants")

// PRESENTATION: overdue > pending > running (Android TimeSheetApp.kt), with iOS's grace.
func present(_ running: RunningShift, hours: Double, grace: Bool, error: Bool) -> ShiftPresentation {
    ShiftSignal.presentation(of: running, now: at(hours), graceElapsed: grace, hasSyncError: error)
}
for grace in [false, true] {
    for error in [false, true] {
        check(present(shift, hours: 1, grace: grace, error: error) == .running,
              "an ACKNOWLEDGED shift is 'Clocked in' whatever the grace and the row's error say - the error is the "
              + "notice's business (grace \(grace), error \(error))")
    }
}
check(present(pendingShift, hours: 0.001, grace: false, error: false) == .running,
      "THE GRACE: a start the server has not answered yet is NOT called 'Not confirmed yet' straight away - an "
      + "online tap is unacknowledged for one request and must not flash a warning at every clock-in")
check(present(pendingShift, hours: 0.001, grace: true, error: false) == .pending,
      "once the grace has run out an unacknowledged start says 'Not confirmed yet'")
check(present(pendingShift, hours: 0.001, grace: false, error: true) == .pending,
      "a sync error ends the grace at once: the server answered and the answer was no")
check(present(pendingShift, hours: 7.99, grace: true, error: true) == .pending,
      "still pending at 7h59: running -> pending needs no clock")
for grace in [false, true] {
    for error in [false, true] {
        check(present(pendingShift, hours: 8, grace: grace, error: error) == .overdue,
              "OVERDUE BEATS PENDING at exactly 8h (grace \(grace), error \(error))")
        check(present(pendingShift, hours: 9, grace: grace, error: error) == .overdue,
              "...and after it")
        let flagged = RunningShift(locationId: shift.locationId, locationName: shift.locationName,
                                   startTime: start, serverAutoClosed: true, pendingConfirmation: true)
        check(present(flagged, hours: 0.5, grace: grace, error: error) == .overdue,
              "a server-flagged auto-close is overdue after 30 minutes even when it is also pending")
        check(present(shift, hours: 9, grace: grace, error: error) == .overdue, "an acknowledged shift past 8h is overdue")
    }
}
check(ShiftSignal.isPending(pendingShift, graceElapsed: true, hasSyncError: false)
      && !ShiftSignal.isPending(pendingShift, graceElapsed: false, hasSyncError: false)
      && ShiftSignal.isPending(pendingShift, graceElapsed: false, hasSyncError: true)
      && !ShiftSignal.isPending(shift, graceElapsed: true, hasSyncError: true),
      "isPending = flag && (grace over || error): only an unacknowledged start can be pending")

// CONFIRMED (used by P7): Android's !pendingConfirmation && syncError == null && !overdue, read off the
// FLAG - the grace never makes an unacknowledged start 'confirmed'.
check(ShiftSignal.isConfirmed(shift, now: at(1), hasSyncError: false), "an acknowledged, error-free, running shift is confirmed")
check(!ShiftSignal.isConfirmed(pendingShift, now: at(1), hasSyncError: false),
      "an unacknowledged start is never confirmed - not even during the grace, when the screen still says 'Clocked in'")
check(!ShiftSignal.isConfirmed(shift, now: at(1), hasSyncError: true), "a row carrying a sync error is not confirmed")
check(!ShiftSignal.isConfirmed(shift, now: at(8), hasSyncError: false), "an overdue shift is not confirmed")
check(!ShiftSignal.isConfirmed(serverClosed, now: at(0.5), hasSyncError: false), "a server-closed shift is not confirmed")

// THE LADDER SAYS IT TOO. Fixed instants, so nothing depends on "now": the flag changes each rung's KIND
// and not its hour, its delay or how many there are - and EVERY rung is 'pending' while pending,
// the 8h one included (a shift the server never heard of was not "closed automatically").
func rungs(_ running: RunningShift, hoursIn: Double) -> [ShiftSignal.Rung] {
    ShiftSignal.ladder(for: running, now: at(hoursIn))
}
for hoursIn in [0.0, 0.5, 1.0, 3.5, 4.0, 7.5, 7.99, 8.0, 9.0] {
    let confirmedRungs = rungs(shift, hoursIn: hoursIn)
    let pendingRungs = rungs(pendingShift, hoursIn: hoursIn)
    check(confirmedRungs.map(\.hour) == pendingRungs.map(\.hour) && confirmedRungs.map(\.delay) == pendingRungs.map(\.delay),
          "pending and confirmed have the same rungs at the same delays (+\(hoursIn)h in): the flag moves no reminder")
    check(pendingRungs.allSatisfy { $0.kind == .pending },
          "EVERY rung of a pending shift says 'Not confirmed yet' (+\(hoursIn)h in), including the 8h one")
    check(confirmedRungs.allSatisfy { $0.kind == ($0.hour == 8 ? .autoClose : .nudge) },
          "a confirmed shift keeps today's two wordings: a nudge, and the auto-close at 8h (+\(hoursIn)h in)")
}
check(rungs(shift, hoursIn: 0).map(\.hour) == [1, 2, 3, 4, 5, 6, 7, 8], "at the moment of the tap all eight rungs are ahead")
check(rungs(pendingShift, hoursIn: 4.5).map(\.hour) == [5, 6, 7, 8] && rungs(pendingShift, hoursIn: 4.5).map(\.kind) == [.pending, .pending, .pending, .pending],
      "re-armed 4h30 in (a relaunch): the rungs left are 5h..8h and all of them are pending")
check(rungs(shift, hoursIn: 4.5).map(\.kind) == [.nudge, .nudge, .nudge, .autoClose],
      "...and when it is confirmed they are the nudges and the auto-close")
check(rungs(shift, hoursIn: 0).first?.delay == 3600 && rungs(shift, hoursIn: 0.25).first?.delay == 2700,
      "a rung's delay is its fire time minus now, to the second")
check(rungs(shift, hoursIn: 8).isEmpty && rungs(pendingShift, hoursIn: 9).isEmpty,
      "no rung is left once the shift is 8h old: nothing new is scheduled past the boundary")
check(ShiftSignal.reminderKind(hour: 8, pendingConfirmation: true) == .pending
      && ShiftSignal.reminderKind(hour: 8, pendingConfirmation: false) == .autoClose
      && ShiftSignal.reminderKind(hour: 1, pendingConfirmation: false) == .nudge,
      "reminderKind: pending first, then the auto-close rung, then the nudge")

// THE ANDROID CHECK'S GREPS (android/checks/core-check.kt, 'CONSTANT PARITY WITH iOS') still match this
// file's text. android/checks/run.sh is the real proof; these are the same three literals, here, so an
// iOS-only edit that breaks them fails on the iOS side first.
let signalSource = try! String(contentsOfFile: "NFCTimeSheets/ShiftSignal.swift", encoding: .utf8)
for literal in ["autoCloseAfter: TimeInterval = 8 * 3600",
                "reminderHours: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]",
                "shiftRunning ? [.log, .materials, .settings] : AppTab.allCases"] {
    check(signalSource.contains(literal), "ShiftSignal.swift still contains '\(literal)' (Android's core-check greps it)")
}
// plan() is not allowed to know the flag AT ALL - that is how "presentation only" is enforced in text.
let planBody = signalSource.components(separatedBy: "static func plan(for running: RunningShift?, now: Date) -> SignalPlan {")[1]
    .components(separatedBy: "// MARK: Spoken duration")[0]
check(!planBody.isEmpty && !planBody.contains("pending") && !planBody.contains("Pending"),
      "ShiftSignal.plan() does not read pendingConfirmation: the flag cannot gate a signal")
check(!signalSource.contains("import SwiftUI") && !signalSource.contains("import UserNotifications") && !signalSource.contains("import ActivityKit"),
      "ShiftSignal.swift is still Foundation-only")

// WIRING, as text (the SwiftUI side cannot be imported here).
func sourceText(_ name: String) -> String {
    try! String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8)
}
func codeOnly(_ s: String) -> String {
    s.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}
func textBetween(_ s: String, _ from: String, _ to: String) -> String {
    let parts = s.components(separatedBy: from)
    return parts.count > 1 ? parts[1].components(separatedBy: to)[0] : ""
}

// The flag is derived from the ROW the server has not acknowledged, in the ONE place a RunningShift is built.
let runningBuilders = (try? FileManager.default.contentsOfDirectory(atPath: "NFCTimeSheets"))?
    .filter { $0.hasSuffix(".swift") && $0 != "ShiftSignal.swift" }
    .filter { codeOnly(sourceText($0)).contains("RunningShift(") } ?? []
check(runningBuilders == ["ContentView.swift"],
      "ContentView.swift is the only file that builds a RunningShift (found \(runningBuilders)): one construction site, one place the flag can be forgotten")
let asRunningBody = textBetween(codeOnly(view), "private func asRunning(_ shift: Shift) -> RunningShift {", "\n    }")
check(asRunningBody.contains("pendingConfirmation: shift.openSyncedAt == nil"),
      "asRunning sets pendingConfirmation from shift.openSyncedAt == nil - the server's acknowledgement is the only thing that clears it")
check(!asRunningBody.contains("syncError") && !asRunningBody.contains("isFullySynced"),
      "...and from nothing else (a close that is still unsent does not make an acknowledged OPEN pending)")

// RE-ARM AFTER THE PUSH (signals-rearm-after-push). iOS freezes a notification's text when it is scheduled, so the
// ladder armed at the tap (pending) must be armed again once the server has answered. The re-arm sits INSIDE the
// tap's own un-awaited Task, after `await syncPending`, and is the session-guarded arm.
let tapTask = handleTap.components(separatedBy: "\n        Task {\n            // Wraps the await rather than")[1]
check(tapTask.contains("await syncPending(context: context, workerId: worker.id)"),
      "handleTap's trailing Task still pushes the queue")
let tapPush = tapTask.range(of: "await syncPending(context: context, workerId: worker.id)")!
let tapRearm = tapTask.range(of: "armIfStillCurrent()")
check(tapRearm != nil && tapPush.upperBound < tapRearm!.lowerBound,
      "handleTap RE-ARMS after `await syncPending` (inside the same un-awaited Task) so 'Not confirmed yet' flips on acceptance")
check(handleTap.components(separatedBy: "signals.arm(").count - 1 == 1,
      "...and the FIRST arm (the unguarded one right after the save) is still the only direct signals.arm( in handleTap")
check(!handleTap.contains("await signals.") && !tapTask.contains("await armIfStillCurrent") && !tapTask.contains("await signals"),
      "no signal call is awaited on the tap path, the re-arm included")
let beforeTapTask = handleTap.components(separatedBy: "\n        Task {\n            // Wraps the await rather than")[0]
check(save!.upperBound < beforeTapTask.range(of: "signals.arm(")!.lowerBound,
      "the first arm still follows context.save()")
let manualStopBody = textBetween(view, "private func manualStop() {", "\n    #if DEBUG")
let msSave = manualStopBody.range(of: "try? context.save()"), msArm = manualStopBody.range(of: "signals.arm(for: currentRunning())")
check(msSave != nil && msArm != nil && msSave!.upperBound < msArm!.lowerBound,
      "manualStop closes and SAVES the local row before it arms")
let msTask = manualStopBody.components(separatedBy: "        Task {\n")
check(msTask.count == 2, "manualStop pushes from exactly one un-awaited Task")
let msPush = msTask[1].range(of: "await syncPending(context: context, workerId: worker.id)")
let msRearm = msTask[1].range(of: "armIfStillCurrent()")
check(msPush != nil && msRearm != nil && msPush!.upperBound < msRearm!.lowerBound,
      "manualStop RE-ARMS after `await syncPending` too (the same one-arm-per-push rule as a tap)")
check(!manualStopBody.contains("await signals.") && !manualStopBody.contains("await armIfStillCurrent"),
      "manualStop awaits no signal call")
check(manualStopBody.components(separatedBy: "signals.arm(").count - 1 == 1,
      "manualStop keeps exactly one direct arm (the one after its save)")

// THE LADDER'S TEXT: ShiftSignalCenter turns each rung into a request and says what its KIND says, pending first.
let ladderBody = textBetween(codeOnly(center), "private func scheduleLadder(for running: RunningShift, center: UNUserNotificationCenter) {", "func requestAuthorizationIfNeeded() async {")
check(ladderBody.contains("ShiftSignal.ladder(for: running, now: .now)") && ladderBody.contains("switch rung.kind {")
      && ladderBody.contains("timeInterval: rung.delay"),
      "scheduleLadder takes its rungs, their kinds and their delays from ShiftSignal.ladder")
let casePending = ladderBody.range(of: "case .pending:"), caseAuto = ladderBody.range(of: "case .autoClose:"),
    caseNudge = ladderBody.range(of: "case .nudge:")
check(casePending != nil && caseAuto != nil && caseNudge != nil
      && casePending!.upperBound < caseAuto!.lowerBound && caseAuto!.upperBound < caseNudge!.lowerBound,
      "the PENDING wording is the FIRST branch of the ladder, before the auto-close one (Android ShiftSignals.postReminder)")
check(!ladderBody.contains("isAutoCloseWarning") && !ladderBody.contains("pendingConfirmation"),
      "scheduleLadder decides nothing itself: no isAutoCloseWarning, no flag read - ShiftSignal.reminderKind is the one rule")
let pendingBranch = textBetween(ladderBody, "case .pending:", "case .autoClose:")
check(pendingBranch.contains("String(localized: \"Not confirmed yet: \\(running.locationName)\")")
      && pendingBranch.contains("String(localized: \"Your time is saved on this phone. Open the app and check the message.\")"),
      "the pending rung is 'Not confirmed yet: <place>' with the saved-on-this-phone body (Android notify_pending_title / _body)")
check(!pendingBranch.contains("closed automatically") && !pendingBranch.contains("Still clocked in"),
      "...and says nothing about an automatic close or a normal shift")
check(codeOnly(center).components(separatedBy: "isAutoCloseWarning").count == 1,
      "ShiftSignalCenter no longer asks isAutoCloseWarning itself")

print("shift-signal-check: OK")
