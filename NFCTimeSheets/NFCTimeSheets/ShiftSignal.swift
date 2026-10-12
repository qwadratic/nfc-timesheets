//
//  ShiftSignal.swift
//  NFCTimeSheets
//
//  What the app believes about the shift in progress, and everything that follows from
//  it: which tabs exist, which out-of-app signals are armed, when the reminders fire.
//
//  FOUNDATION ONLY, on purpose. No SwiftUI, no UserNotifications, no ActivityKit. That
//  is what lets checks/shift-signal-check.swift cat this file and run it on a Mac with
//  no Xcode, no simulator and no phone - the same trick TagLink.swift and TapInbox.swift
//  already use. Every rule that decides whether a worker is reminded to tap out lives
//  here, where it can be proven; the platform plumbing lives in ShiftSignalCenter.swift,
//  where it cannot.
//
//  Mirrored one-for-one by android/.../core/ShiftSignal.kt. The two files are the same
//  state machine written twice, and android/checks/core-check.kt asserts the constants
//  agree - the whole point of this work is that the two platforms behave the same.
//

import Foundation

// MARK: - What the app believes

/// The open shift, as the app currently understands it. Built from the LOCAL SwiftData
/// row, which is what a tap in a basement writes - never from a server response, because
/// there may not have been one.
///
/// This is the single value the signal is armed from (audit §4): the tap path and
/// `adoptServerOpenShift` both end up calling `ShiftSignalCenter.arm(for:)` with one of
/// these, so a reinstalled phone re-arms exactly like a fresh clock-in does.
struct RunningShift: Equatable {
    let locationId: String
    /// May be the "unknown location" fallback: the roster cache is filled by the network
    /// and a tag tap does not wait for it. A missing NAME is cosmetic; a missing SHIFT is
    /// unpaid work. Nothing here branches on it.
    let locationName: String
    let startTime: Date
    /// The server has already flagged this shift as auto-closed and no human has
    /// confirmed the real finish time (decision-10). Forces `.overdue` regardless of the
    /// clock: a shift the server has closed must never be shown with a running timer.
    let serverAutoClosed: Bool
    /// PRESENTATION ONLY (Android 60f6886 RunningShift.pendingConfirmation): this start exists
    /// only on the phone - the server has not acknowledged it (`Shift.openSyncedAt == nil`).
    ///
    /// It is read by exactly two things, and both only choose WORDS: the running screen
    /// (heading, state word, spoken label, the notice under the clock) and the reminder
    /// ladder's text. It never gates, delays or alters a clock-in, a sync, an hours figure, or
    /// what is shown or hidden: `plan(for:now:)` does not read it, so the lock, the badge, the
    /// ladder's timing and the 8h phase of a pending shift are identical to a confirmed one's,
    /// and the clock keeps counting from the local start. checks/shift-signal-check.swift pins it.
    let pendingConfirmation: Bool

    init(locationId: String, locationName: String, startTime: Date, serverAutoClosed: Bool = false,
         pendingConfirmation: Bool = false) {
        self.locationId = locationId
        self.locationName = locationName
        self.startTime = startTime
        self.serverAutoClosed = serverAutoClosed
        self.pendingConfirmation = pendingConfirmation
    }
}

/// Two phases and no more. `running` is a normal shift; `overdue` is one that has passed
/// (or been confirmed past) the 8h auto-close boundary and now needs a human.
enum ShiftPhase: String, Equatable {
    case running
    case overdue
}

/// What the running screen SAYS about the open shift, strongest first: overdue > pending >
/// running (Android TimeSheetApp.kt: heading, state word and spoken label alike). A way of
/// describing the same running clock, never a phase: nothing but words reads it.
enum ShiftPresentation: String, Equatable {
    case overdue
    case pending
    case running
}

/// Which of three wordings one reminder rung carries. Only the TEXT differs - the rung's time,
/// its identifier and the ladder's shape are the same for all three, and so is whether a
/// ladder exists at all (`ShiftSignal.plan`).
enum ReminderKind: String, Equatable {
    /// The start has not been acknowledged by the server. EVERY rung says so, the 8h one
    /// included: a shift the server never heard of was not "closed automatically".
    case pending
    /// The 8h rung of a confirmed shift: the server has just closed it.
    case autoClose
    /// The ordinary "you are still clocked in" nudge.
    case nudge
}

// MARK: - The lock

/// The tabs that exist. NOT a security boundary and NOT a kiosk - a WORK-DISCIPLINE
/// shape. While a shift runs the app has one job and looks like it. Anyone reading this
/// later: do not mistake it for enforcement. The worker can sign out, resolve an
/// auto-closed shift, ask for material and read the help text at every moment, and every
/// one of those is a labelled tab rather than a gesture or a PIN.
enum AppTab: String, CaseIterable {
    case log
    case materials
    case history
    case settings
}

enum ShiftSignal {

    // MARK: Constants shared with the server's 8h timer

    /// ops/sql/autoclose.sql closes an open shift at start + 8h and the systemd timer
    /// runs it every 15 minutes (decision-10). The client computes the same boundary
    /// LOCALLY and never asks the server for it: a clock-in works offline, so a
    /// server-supplied deadline would be a second mechanism the client cannot rely on.
    /// One constant on each side, both pinned by checks.
    static let autoCloseAfter: TimeInterval = 8 * 3600

    /// Escalating reminders, in hours after the start. The last rung is the auto-close
    /// itself, so its wording is different - see `isAutoCloseWarning`.
    ///
    /// One-shot requests, not a repeating trigger: `UNTimeIntervalNotificationTrigger`
    /// with `repeats: true` demands >= 60s and then says the same thing forever, and
    /// "Sie sind seit 5 Stunden eingestempelt" is worth more than eight identical pings.
    /// Eight pending requests is nowhere near the system's 64-soonest ceiling.
    static let reminderHours: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]

    /// The 8h rung is not "you have been clocked in for 8 hours", it is "the server has
    /// just closed this and you now have to confirm the real finish time".
    static func isAutoCloseWarning(hour: Int) -> Bool {
        TimeInterval(hour) * 3600 >= autoCloseAfter
    }

    // MARK: Phase

    static func phase(startTime: Date, now: Date, serverAutoClosed: Bool) -> ShiftPhase {
        if serverAutoClosed { return .overdue }
        return now.timeIntervalSince(startTime) >= autoCloseAfter ? .overdue : .running
    }

    static func phase(of running: RunningShift, now: Date) -> ShiftPhase {
        phase(startTime: running.startTime, now: now, serverAutoClosed: running.serverAutoClosed)
    }

    /// The moment the server's timer will close this shift. Used to bound the ticking
    /// clock so it stops at 8h instead of counting to infinity.
    static func autoCloseDeadline(after startTime: Date) -> Date {
        startTime.addingTimeInterval(autoCloseAfter)
    }

    // MARK: What the running screen SAYS (presentation only)

    /// Does the screen CLAIM "not confirmed yet"? The start is unacknowledged AND either the
    /// grace has run out or the sync already left a sentence on the row.
    ///
    /// THE ONE DELIBERATE DEVIATION FROM ANDROID. iOS writes the row BEFORE the POST
    /// (handleTap), so every online tap is unacknowledged for one request. Saying "Not
    /// confirmed yet" for that half-second would make a phone that works look broken at every
    /// clock-in, so the claim waits `PendingNotice.grace` (2 s) - unless there is already
    /// something to report: a sync error ends the wait at once (the server answered, and the
    /// answer was no), and so does a start that is already old
    /// (`PendingNotice.graceElapsedAtOnce`). The FLAG is not delayed by any of this:
    /// `pendingConfirmation` is true from the first frame, and the ladder reads the flag.
    static func isPending(_ running: RunningShift, graceElapsed: Bool, hasSyncError: Bool) -> Bool {
        running.pendingConfirmation && (graceElapsed || hasSyncError)
    }

    static func presentation(of running: RunningShift, now: Date, graceElapsed: Bool,
                             hasSyncError: Bool) -> ShiftPresentation {
        if phase(of: running, now: now) == .overdue { return .overdue }
        return isPending(running, graceElapsed: graceElapsed, hasSyncError: hasSyncError) ? .pending : .running
    }

    /// Android's `confirmed = !running.pendingConfirmation && syncError == null && !overdue`.
    /// Read off the FLAG, not off the grace: during the grace the server has still not said
    /// yes, so the motion that celebrates a confirmation (P7) waits for the real acknowledgement.
    static func isConfirmed(_ running: RunningShift, now: Date, hasSyncError: Bool) -> Bool {
        !running.pendingConfirmation && !hasSyncError && phase(of: running, now: now) == .running
    }

    // MARK: What a reminder SAYS (presentation only)

    /// Pending first, then the auto-close rung, then the nudge (Android
    /// ShiftSignals.postReminder). iOS fixes a notification's text WHEN IT IS SCHEDULED, so this
    /// is evaluated at every arm, and the signals are re-armed after the tap's own push
    /// (ContentView.handleTap, manualStop) - the wording flips when the server says yes.
    static func reminderKind(hour: Int, pendingConfirmation: Bool) -> ReminderKind {
        if pendingConfirmation { return .pending }
        return isAutoCloseWarning(hour: hour) ? .autoClose : .nudge
    }

    /// One rung that is still to fire: which hour it is, how long from `now`, what it says.
    struct Rung: Equatable {
        let hour: Int
        let delay: TimeInterval
        let kind: ReminderKind
    }

    /// The rungs ShiftSignalCenter schedules, as a value: +1h .. +8h after the start, rungs already
    /// in the past skipped (re-arming four hours in gives 5h, 6h, 7h and 8h and nothing else).
    /// The flag changes each rung's KIND and nothing about WHEN or HOW MANY - so this is the pure
    /// half of the ladder, provable on a Mac at fixed instants, and the platform half only turns
    /// each rung into a notification request.
    static func ladder(for running: RunningShift, now: Date) -> [Rung] {
        reminderHours.compactMap { hour in
            let delay = running.startTime.addingTimeInterval(TimeInterval(hour) * 3600).timeIntervalSince(now)
            guard delay > 0 else { return nil }
            return Rung(hour: hour, delay: delay,
                        kind: reminderKind(hour: hour, pendingConfirmation: running.pendingConfirmation))
        }
    }

    // MARK: The lock

    /// History is the only thing that goes away, and nothing in it is time-critical.
    ///
    /// Materials stays because the worker is standing IN the building - that is exactly
    /// when they need it. Settings stays because a handed-over phone must be signable-out
    /// (decision-22/26). Log stays because it has become the shift screen. The resolver
    /// is not a tab: it is a banner on the Log tab and it is shown in EVERY state, which
    /// is what decision-10 requires.
    static func visibleTabs(shiftRunning: Bool) -> [AppTab] {
        shiftRunning ? [.log, .materials, .settings] : AppTab.allCases
    }

    // MARK: The permission moment

    /// NEVER on the clock-in path, and never before the first successful clock-in.
    ///
    /// The alternative was asking at launch, which means asking at a door at 06:02 with
    /// gloves on, before the worker has any idea what the app is for - and a "Don't
    /// Allow" there is permanent. Ask once, afterwards, from a screen that is already
    /// explaining what the reminder buys. A refusal is a weaker signal and one sentence,
    /// never a blocked tap and never a nag.
    static func shouldAskForNotifications(hasClockedIn: Bool, alreadyAsked: Bool) -> Bool {
        hasClockedIn && !alreadyAsked
    }

    // MARK: The plan

    /// Everything the OS should be showing right now, derived from one value.
    ///
    /// `plan(for: nil)` is `.idle` - every signal off. That is the invariant that keeps a
    /// closed shift from leaving a badge on the home screen or a Live Activity on the
    /// lock screen, and it is why the arming call is unconditional rather than guarded by
    /// "did something change".
    struct SignalPlan: Equatable {
        /// The Log tab renders the full-bleed shift screen instead of the list.
        let lockScreen: Bool
        /// The app-icon badge. AN OPEN SHIFT OWNS THE APP-ICON BADGE; materials never
        /// touch it - the icon badge carries one number and two owners would fight over
        /// it. The Materials TAB badge is a different thing and does not collide.
        let badgeCount: Int
        /// The +1h..+8h ladder is pending.
        let remindersScheduled: Bool
        /// A Live Activity should be running. Inert until the owner adds the widget
        /// extension target (docs/LIVE-ACTIVITY-SETUP.md); the controller no-ops.
        let liveActivity: Bool
        let phase: ShiftPhase?

        static let idle = SignalPlan(lockScreen: false, badgeCount: 0,
                                     remindersScheduled: false, liveActivity: false, phase: nil)
    }

    static func plan(for running: RunningShift?, now: Date) -> SignalPlan {
        guard let running else { return .idle }
        let phase = phase(of: running, now: now)
        return SignalPlan(
            lockScreen: true,
            // Still 1 when overdue: the shift is still the only thing this app is about,
            // and the worker still has to act - harder now, not less.
            badgeCount: 1,
            // Past 8h every rung has already fired and the server has closed the shift.
            // Re-arming would ping somebody about a shift that no longer exists.
            remindersScheduled: phase == .running,
            // ActivityKit hard-ends a Live Activity at 8 hours - exactly the auto-close
            // window. There is no extension and asking for one past the boundary is a
            // request the system refuses. Do not promise "it stays until you tap out".
            liveActivity: phase == .running,
            phase: phase
        )
    }

    // MARK: Spoken duration

    /// Hours and minutes, for the ONE static accessibility element that carries the
    /// elapsed time.
    ///
    /// The ticking text on screen is `accessibilityHidden`. A per-second live region
    /// makes VoiceOver unusable, and a locked screen whose only content is a timer is
    /// precisely where that bug would be worst. The label is recomputed once a minute by
    /// a TimelineView, which updates the label without announcing anything.
    static func elapsed(from startTime: Date, to now: Date) -> (hours: Int, minutes: Int) {
        let seconds = max(0, Int(now.timeIntervalSince(startTime)))
        return (seconds / 3600, (seconds % 3600) / 60)
    }

    // MARK: The typographic clock (presentation only)

    /// The elapsed time as the TWO runs the running screen draws (Android ShiftTimeDisplay.kt
    /// `ElegantTime`): `main` is "HH:MM" with the hours zero-padded to two digits, drawn large, and
    /// `seconds` is "SS", drawn at about a third of its size on the same baseline. Locale-independent on
    /// purpose - these are digits, not prose, and Austria reads 03:07 the same way everywhere.
    ///
    /// CLAMPED to 0...8 h: a phone whose clock jumped backwards reads 00:00 00 and a stale tick past the
    /// boundary never draws 08:00 01 (past 8 h the screen is `.overdue` and draws `overdueClock`).
    static func clockParts(from startTime: Date, to now: Date) -> (main: String, seconds: String) {
        let total = min(max(0, Int(now.timeIntervalSince(startTime))), Int(autoCloseAfter))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return (String(format: "%02d:%02d", hours, minutes), String(format: "%02d", seconds))
    }

    /// What the clock reads once the 8 h boundary has passed: Android's "8:00:00+", split the same way
    /// (`8` padded to `08`, the `00+` as the small run). Not a running number.
    static let overdueClock: (main: String, seconds: String) = ("08:00", "00+")
}
