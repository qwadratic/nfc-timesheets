// Runnable check: the in-shift state machine. No test framework, no Xcode, no simulator.
//
//   cd NFCTimeSheets
//   cat NFCTimeSheets/ShiftSignal.swift checks/shift-signal-check.swift \
//     > /tmp/shift-signal-check.swift && swift /tmp/shift-signal-check.swift
//
// Four things are pinned here, and every one of them is a way this feature could quietly
// cost somebody money:
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

print("shift-signal-check: OK")
