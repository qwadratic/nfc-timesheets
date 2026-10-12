//
//  ShiftReceipt.swift
//  NFCTimeSheets
//
//  WHEN THE IDLE LIST SHOWS A "SHIFT FINISHED" RECEIPT, and what its delivery line says (decision-83,
//  TASK-365.8 / iOS P7). Ported from Android's TimeSheetApp.kt at 60f6886 (`showReceipt`,
//  `CompletedShiftReceipt`) and docs/ANDROID-WORKER-DESIGN.md "Final composition": "A receipt entered
//  within two minutes stays until Continue; it does not disappear during reading."
//
//  FOUNDATION-ONLY ON PURPOSE, and it needs PendingWork.swift cat-ed in front of it (the one
//  predicate for "does the server have this row"): checks/shift-receipt-check.swift runs this file on
//  a Mac with no Xcode, at fixed instants. The view that draws the answer is ShiftReceiptView.swift;
//  the SwiftUI side only holds a `Memory` in @State and asks it.
//
//  THE OFFER (Android `rememberSaveable(latest.clientUuid, latest.endTime) { age in 0..120 }`):
//    - the candidate is the signed-in worker's NEWEST finished row, and only that one;
//    - it is OFFERED when its finish is 0-120 whole seconds old at the moment it is first seen
//      (floored, like Java's `Duration.seconds`, so a finish in the future is never offered);
//    - the offer is CAPTURED, and a captured offer STAYS - past 120 s, through re-renders - until the
//      worker presses Continue, because a receipt that vanished while somebody was reading it is
//      exactly what the two minutes were meant to prevent;
//    - a DISMISSED receipt is never offered again, and a different finished row (or the same row
//      finished again a second or more later - a 422 proof_required reopen) is a new offer;
//    - a fresh launch re-evaluates from the store: a receipt older than two minutes is not offered.
//
//  IDENTITY IS TOLERANT TO THE SERVER'S ROUNDING. The finish time the phone wrote is a `Date` with
//  sub-millisecond precision; the server stores what the phone sent and echoes it back as
//  millisecond ISO-8601, and `apply()` (Sync.swift) overwrites `endTime` with that echo. Compared
//  exactly, the receipt's identity would CHANGE when the ACK lands and a dismissed receipt would
//  come back. So two finish times within 1 s are the same finish.
//
//  PRESENTATION ONLY. Nothing here is read by a tap, a sync pass, a signal or navigation, and
//  nothing here writes or deletes a shift.
//
//  THE DELIVERY LINE says what is TRUE about delivery, from PendingWork.state (the same predicate
//  syncPending iterates and the count rows use), in four states:
//      .problem  the row carries a recorded sentence (red when nobody will retry it)
//      .sent     the server has everything it will get from this row
//      .sending  a request for this tap is still inside the 2 s grace (iOS writes BEFORE it posts,
//                so an online stop would otherwise flash "not confirmed" for one request)
//      .savedLocally   the phone holds it and the server has not said yes
//  A finished-but-unsent shift therefore shows its delivery state here and never a check. It is a
//  SEPARATE question from `isConfirmed` below (Android reuses one flag for both and prints "saved
//  on this phone" under a delivered row that merely needs its finish time confirmed).
//

import Foundation

enum ShiftReceipt {

    // MARK: The offer

    /// Android: `Duration.between(end, now).seconds in 0..120`.
    static let offerWindowSeconds = 120

    /// Whole seconds floored, in 0...120. A finish in the future (a phone whose clock is behind the
    /// one that wrote it) is not offered.
    static func isRecent(endedAt: Date, now: Date) -> Bool {
        let seconds = now.timeIntervalSince(endedAt)
        guard seconds.isFinite else { return false }
        let whole = Int(max(min(seconds.rounded(.down), 1e9), -1e9))
        return (0...offerWindowSeconds).contains(whole)
    }

    /// WHICH receipt: the row and the finish it was offered for.
    struct Identity: Equatable {
        let clientUuid: String
        let endedAt: Date

        /// Two finish times closer than this are the same finish (see the header).
        static let tolerance: TimeInterval = 1

        static func == (lhs: Identity, rhs: Identity) -> Bool {
            lhs.clientUuid == rhs.clientUuid && abs(lhs.endedAt.timeIntervalSince(rhs.endedAt)) < tolerance
        }
    }

    /// What the screen remembers between renders. A value, so the whole rule runs on a Mac and the
    /// view holds exactly one `@State` of it.
    struct Memory: Equatable {
        /// The receipt that was offered and is still waiting for Continue.
        private(set) var captured: Identity?
        /// The receipt the worker pressed Continue on.
        private(set) var dismissed: Identity?

        init() {}

        /// The identity whose receipt is up for `latest` at `now`, or nil. Derived, never stored, so
        /// the FIRST frame after a finish already shows the receipt (no frame of the start controls
        /// before the capture lands).
        func offer(for latest: Identity?, now: Date) -> Identity? {
            guard let latest else { return nil }
            if let dismissed, dismissed == latest { return nil }
            if let captured, captured == latest { return latest }
            return ShiftReceipt.isRecent(endedAt: latest.endedAt, now: now) ? latest : nil
        }

        /// Called when the newest finished row appears or changes: keeps the offer, so it outlives
        /// the 120 s window. Idempotent.
        mutating func observe(_ latest: Identity?, now: Date) {
            guard let offered = offer(for: latest, now: now) else { return }
            captured = offered
        }

        /// Continue. Remembered against the identity, so the same receipt never comes back.
        mutating func dismiss(_ latest: Identity?) {
            guard let latest else { return }
            dismissed = latest
        }
    }

    // MARK: The delivery line

    enum Delivery: Equatable {
        /// The row's own, already-localised sentence (Sync.swift stores APIFailure.workerMessage).
        /// `blocked` = nobody is retrying: a human has to act, so it is drawn in the error colour.
        case problem(String, blocked: Bool)
        case sent
        case sending
        case savedLocally
    }

    static func delivery(row: PendingRow, syncError: String?, now: Date) -> Delivery {
        if let syncError, !syncError.isEmpty { return .problem(syncError, blocked: row.syncBlocked) }
        if PendingWork.state(of: row) == .delivered { return .sent }
        if PendingWork.isInFlight(row, now: now) { return .sending }
        return .savedLocally
    }

    // MARK: The gate for the clock-out motion

    /// Android: `confirmed = isFullySynced && syncError == null && !needsResolution`. ONLY the
    /// motion reads it: a finish that still needs its time resolved is delivered (the line says
    /// "Sent") but is not something to celebrate.
    static func isConfirmed(row: PendingRow, syncError: String?, needsResolution: Bool) -> Bool {
        PendingWork.state(of: row) == .delivered && (syncError ?? "").isEmpty && !needsResolution
    }

    // MARK: The pills

    enum Badge: Hashable {
        /// decision-56 section 5: "every list that shows shifts must show this".
        case manual
        case corrected
        case autoClosed
    }

    /// ShiftRow's chain for a FINISHED row, in its order: Manual, then Auto-closed or Corrected.
    static func badges(manualStart: Bool, manualClose: Bool, autoClosed: Bool, correctedAt: Date?) -> [Badge] {
        var badges: [Badge] = []
        if manualStart || manualClose { badges.append(.manual) }
        if autoClosed && correctedAt == nil {
            badges.append(.autoClosed)
        } else if correctedAt != nil {
            badges.append(.corrected)
        }
        return badges
    }
}
