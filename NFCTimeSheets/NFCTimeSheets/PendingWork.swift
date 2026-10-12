//
//  PendingWork.swift
//  NFCTimeSheets
//
//  WHAT THIS PHONE IS STILL HOLDING, as pure functions (decision-82, TASK-365.7 / iOS P6). Ported
//  from Android's core/PendingWork.kt at 60f6886 (TASK-225: "a tap in a basement was written to
//  SQLite and, until this iteration, nobody could even ask whether it had happened").
//
//  THREE READERS, one number: the idle list, the running screen and the SIGN-IN screen - because
//  signing out deletes nothing and the person holding the phone must not think it went away. The
//  views are DeliveryStatusViews.swift; this file is only the arithmetic and the wording DECISION,
//  and it is FOUNDATION-ONLY on purpose (like WorkerScope / ShiftSignal / PendingNotice) so that
//  checks/pending-work-check.swift runs it on a Mac with no Xcode.
//
//  THE ONE PREDICATE. `state(of:)` is the only definition of "does the server have this row yet".
//  Sync.swift's `syncPending` iterates exactly the `.waiting` rows and this file counts exactly the
//  same three states, so "what the engine will try" and "what the screen says" cannot drift apart:
//  one that disagreed would either nag about a shift that is safely filed or - far worse - stay
//  quiet about one that is not.
//
//  PRESENTATION ONLY, like the flag P5 added. Nothing here gates, delays or alters a clock-in, a
//  sync, an accounting figure or navigation, and nothing here deletes a row: a blocked shift stays
//  on the phone for the office to look at (TASK-362).
//
//  THE iOS DEVIATIONS from Android, each on purpose:
//   - NO background delivery exists on iOS (Sync.swift), so `delivery_automatic` (Android's "your
//     phone will try again automatically") and its force-stop note are NOT ported and there is no
//     `armed` input: the only waiting sentences are "open the app" and "sign in". See `WaitingSentence`.
//   - LAST ATTEMPT is one global date, not a per-row maximum: a SwiftData column on `Shift` risks the
//     store of unpushed shifts (a failed lightweight migration is a fatalError at launch) for a line
//     of text. `DeliveryAttempt` below stamps it in UserDefaults before every request.
//   - A finish that is OWED WITH A PROOF (Shift.pendingEvidenceEnd, shift evidence) is waiting even
//     though the row is still open locally: syncPending pushes it, so the count must say so.
//

import Foundation

// MARK: - The row

/// The facts about one `Shift` that delivery needs - a value, so this file never sees SwiftData.
/// Built from a `Shift` in Sync.swift (`Shift.deliveryRow`).
struct PendingRow: Equatable {
    /// When the shift started: "the time to tell the office".
    let startTime: Date
    /// nil = the server has not been told this shift started.
    let openSyncedAt: Date?
    /// nil = the server has not been told it finished.
    let closeSyncedAt: Date?
    /// The shift has no end time on the phone (it is still running, or was reopened by a refused close).
    let isOpen: Bool
    /// Terminal refusal (or a row queued by another account): nobody retries it, a human has to act.
    let syncBlocked: Bool
    /// A finish that carries a photo proof is owed to the server while the row is still open locally
    /// (Shift.pendingEvidenceEnd != nil). syncPending pushes that close, so it is not "delivered".
    let finishOwed: Bool
    /// Queued under ANOTHER account than the one signed in (always false with nobody signed in).
    /// Only the wording reads it: those rows go out when their own account signs back in.
    let queuedByAnotherAccount: Bool
    /// The moment of the row's last LOCAL write: the finish (or the proof-close) when there is one, else
    /// the start. Only `PendingWork.isInFlight` reads it - to tell "the request for this tap has not
    /// been answered yet" from "this row is waiting".
    let lastChangedAt: Date

    init(startTime: Date, openSyncedAt: Date?, closeSyncedAt: Date?, isOpen: Bool, syncBlocked: Bool,
         finishOwed: Bool = false, queuedByAnotherAccount: Bool = false, lastChangedAt: Date? = nil) {
        self.startTime = startTime
        self.openSyncedAt = openSyncedAt
        self.closeSyncedAt = closeSyncedAt
        self.isOpen = isOpen
        self.syncBlocked = syncBlocked
        self.finishOwed = finishOwed
        self.queuedByAnotherAccount = queuedByAnotherAccount
        self.lastChangedAt = lastChangedAt ?? startTime
    }
}

// MARK: - The count

enum PendingWork {

    enum State: Equatable {
        /// The server has everything it is going to get from this row for now.
        case delivered
        /// Not delivered and somebody will retry it: the next sync pass.
        case waiting
        /// Not delivered and NOBODY will retry it: a terminal refusal or another account's row.
        case blocked
    }

    /// Shift.isFullySynced, verbatim: the open landed AND (the shift is still open, or the close landed).
    static func isFullySynced(_ row: PendingRow) -> Bool {
        row.openSyncedAt != nil && (row.isOpen || row.closeSyncedAt != nil)
    }

    /// THE predicate. An open shift whose OPEN landed is NOT pending - the server has it, the 8h net
    /// applies to it, and it is waiting for a tap that has not happened yet (this includes a row a
    /// 422 proof_required REOPENED: open again, not blocked). A finish owed with a proof is.
    static func state(of row: PendingRow) -> State {
        if isFullySynced(row) && !row.finishOwed { return .delivered }
        return row.syncBlocked ? .blocked : .waiting
    }

    // MARK: The grace

    /// How long a tap's own request may be unanswered before its row is SAID to be waiting. iOS writes
    /// the row BEFORE the POST (unlike Android), so every online clock-in and clock-out is "not
    /// delivered" for the length of one request; without this the idle list would pop a "1 shift still
    /// on this phone" button in and out after every normal tap. It is PendingNotice.grace on purpose
    /// (checks/pending-work-check.swift pins that they agree): the running screen's "Not confirmed yet"
    /// heading and this row appear at the same moment.
    static let settleGrace: TimeInterval = 2

    /// A WAITING row whose last local write is younger than the grace: a request in flight, not a
    /// delivery problem. Never a BLOCKED row (the server has answered, and the answer was no) and never
    /// an old one. A phone whose clock jumped backwards (a negative age) is NOT held back: a row must
    /// not stay hidden because of a skewed clock.
    static func isInFlight(_ row: PendingRow, now: Date) -> Bool {
        guard state(of: row) == .waiting else { return false }
        let age = now.timeIntervalSince(row.lastChangedAt)
        return age >= 0 && age < settleGrace
    }

    /// The rows the screens may COUNT at `now`: everything but a request still in flight.
    static func settled(_ rows: [PendingRow], now: Date) -> [PendingRow] {
        rows.filter { !isInFlight($0, now: now) }
    }

    /// When the earliest held-back row stops being held back (nil = nothing is), so the screen can wake
    /// exactly then - a failed push changes no row after the first 50 ms and nothing else would redraw it.
    static func nextSettle(_ rows: [PendingRow], now: Date) -> Date? {
        rows.filter { isInFlight($0, now: now) }.map { $0.lastChangedAt.addingTimeInterval(settleGrace) }.min()
    }

    // MARK: Summary

    struct Summary: Equatable {
        /// Rows the next sync pass will try.
        let waiting: Int
        /// Rows that will NEVER go out without a human. Counted SEPARATELY and never folded into
        /// `waiting`: "wait for a signal" and "phone the office" are opposite instructions.
        let blocked: Int
        /// How many of the `waiting` rows belong to another account than the signed-in one.
        let waitingForOthers: Int
        /// The start of the earliest unsent shift, waiting OR blocked: how long ago the work the
        /// server has never heard of was actually done. The time to tell the office.
        let oldestStart: Date?
        /// The last time this phone tried to send anything - see `DeliveryAttempt` for what that is
        /// and why it is global. nil = never tried, which the sheet says in words.
        let lastAttemptAt: Date?

        var total: Int { waiting + blocked }
        var isEmpty: Bool { total == 0 }
    }

    static let nothing = Summary(waiting: 0, blocked: 0, waitingForOthers: 0, oldestStart: nil, lastAttemptAt: nil)

    /// Every row the phone holds, device-wide (the caller reads them through WorkerScope).
    ///
    /// `lastAttemptAt` is the global stamp. It is reported only when it is not EARLIER than the
    /// earliest unsent start: an attempt that predates a row cannot have been about it, and a stale
    /// stamp from a long-delivered shift would otherwise read "Last attempt: yesterday" under a
    /// shift that was never tried. It is reported as-is otherwise, never invented.
    static func summarise(_ rows: [PendingRow], lastAttemptAt: Date?) -> Summary {
        var waiting = 0, blocked = 0, others = 0
        var oldest: Date?
        for row in rows {
            switch state(of: row) {
            case .delivered: continue
            case .waiting:
                waiting += 1
                if row.queuedByAnotherAccount { others += 1 }
            case .blocked: blocked += 1
            }
            if oldest == nil || row.startTime < oldest! { oldest = row.startTime }
        }
        var attempt: Date?
        if let oldest, let lastAttemptAt, lastAttemptAt >= oldest { attempt = lastAttemptAt }
        return Summary(waiting: waiting, blocked: blocked, waitingForOthers: others,
                       oldestStart: oldest, lastAttemptAt: attempt)
    }

    // MARK: Wording

    /// The ONE sentence under the waiting count (Android: signedOut -> delivery_sign_in, !armed ->
    /// delivery_not_scheduled, else delivery_automatic). iOS has no `armed` and no automatic
    /// delivery, so the third arm does not exist:
    ///   - `.signIn`    nobody is signed in, or every waiting row belongs to another account:
    ///                  opening the app cannot send them, signing in as their account can.
    ///   - `.notActive` "Automatic delivery is not currently active. Open the app with an internet
    ///                  connection to try delivery again." - true on iOS at every moment.
    /// In a MIX the signed-in worker's own rows win: the sentence must be true for the rows they
    /// can actually act on.
    enum WaitingSentence: Equatable {
        case signIn
        case notActive
    }

    /// nil when nothing is waiting: no sentence under a count that is not on screen.
    static func waitingSentence(for summary: Summary, signedOut: Bool) -> WaitingSentence? {
        guard summary.waiting > 0 else { return nil }
        if signedOut || summary.waitingForOthers == summary.waiting { return .signIn }
        return .notActive
    }
}

// MARK: - The last attempt

/// "A push was tried, now" - Android's markAttempted, with ONE date for the whole phone.
///
/// Stamped IMMEDIATELY BEFORE each request the sync pass (or the proof-close) makes for a row, and
/// for both outcomes: a process killed mid-request would otherwise leave a phone that has tried a
/// hundred times still telling the worker it never did. A row that is skipped without a request
/// (another account's close, a terminally blocked one) stamps nothing, exactly as on Android.
///
/// GLOBAL, NOT PER ROW - the documented deviation. After a successful delivery the stamp can belong
/// to a different row than the one the sheet is about; `PendingWork.summarise` only shows it when
/// it is not earlier than the earliest unsent start.
enum DeliveryAttempt {
    static let defaultsKey = "delivery.lastAttemptAt"

    static func stamp(at now: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: defaultsKey)
    }

    /// 0 / absent = never (the value @AppStorage hands the screens).
    static func date(seconds: Double) -> Date? {
        seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    static func last(in defaults: UserDefaults = .standard) -> Date? {
        date(seconds: defaults.double(forKey: defaultsKey))
    }
}
