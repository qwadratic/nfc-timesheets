//
//  PendingNotice.swift
//  NFCTimeSheets
//
//  The decision behind the one line under the running clock: "this start exists only on this
//  phone" (or the server's reason it is not there), with a Refresh button next to it. Mirrors
//  Android's TimeSheetApp.kt (60f6886): the line shows while `pendingConfirmation || syncError
//  != null`, says the row's own error sentence when there is one and "Saved on this phone" when
//  there is not.
//
//  FOUNDATION ONLY, on purpose, and needs ShiftSignal.swift cat-ed in front of it (RunningShift
//  and ShiftSignal.isPending): checks/pending-notice-check.swift runs this file on a Mac with no
//  Xcode, so the wording decision and the grace are proven rather than assumed. The view that
//  draws the result is PendingNoticeView.swift.
//
//  PRESENTATION ONLY, like the flag it reads. Nothing here gates, delays or alters a clock-in, a
//  sync, an accounting figure or navigation: the clock keeps counting and no control is hidden
//  while this line is up. It also never deletes anything - a refused (blocked) row stays on the
//  phone for the office to look at (TASK-362).
//

import Foundation

enum PendingNotice {

    // MARK: The grace

    /// How long a start may stay unacknowledged before the screen says so. iOS writes the row
    /// BEFORE the POST, so an online tap is unacknowledged for the length of one request; two
    /// seconds covers a normal one with room to spare and is short enough that a phone with no
    /// signal says so while the worker is still looking at it. See ShiftSignal.isPending.
    static let grace: TimeInterval = 2

    /// A start older than this is not "a tap that has not been answered yet": the app was
    /// reopened (or came back to the foreground) with an old unacknowledged row, and the grace
    /// would only make the screen call it "Clocked in" for two more seconds for no reason.
    static let staleAfter: TimeInterval = 10

    /// True at once - no waiting - when the start is already old or the row already carries
    /// a sync error. `now` is the REAL now (Date.now), not the screen's once-a-minute tick.
    static func graceElapsedAtOnce(startedAt: Date, now: Date, hasSyncError: Bool) -> Bool {
        hasSyncError || now.timeIntervalSince(startedAt) >= staleAfter
    }

    // MARK: The notice

    enum Content: Equatable {
        /// The start is only on this phone and nothing has said why.
        case savedLocally
        /// The row's own, already-localised sentence (Sync.swift). `blocked` means nobody is
        /// retrying: the sentence is drawn with a red icon, and the office has to act.
        case problem(String, blocked: Bool)
    }

    /// nil = no notice. The line follows the flag and the error, NOT the overdue > pending >
    /// running precedence that picks the heading (Android does the same): a start that is still
    /// unacknowledged after 8 hours keeps its notice and its Refresh button under "Over 8 hours".
    static func content(pending: Bool, syncError: String?, syncBlocked: Bool) -> Content? {
        if let syncError, !syncError.isEmpty { return .problem(syncError, blocked: syncBlocked) }
        return pending ? .savedLocally : nil
    }

    /// The whole decision from what the screen has: the running shift, whether the grace has
    /// run out (`graceElapsed`, the screen's @State) and the open row's sync fields.
    static func content(for running: RunningShift, graceElapsed: Bool,
                        syncError: String?, syncBlocked: Bool) -> Content? {
        let hasError = !(syncError ?? "").isEmpty
        return content(pending: ShiftSignal.isPending(running, graceElapsed: graceElapsed, hasSyncError: hasError),
                       syncError: syncError, syncBlocked: syncBlocked)
    }
}
