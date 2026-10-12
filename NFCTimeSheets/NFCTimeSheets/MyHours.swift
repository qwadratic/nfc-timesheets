//
//  MyHours.swift
//  NFCTimeSheets
//
//  "MY HOURS": THE WORKER'S LAST 60 DAYS, AS THE SERVER HAS THEM (decision-83, TASK-365.8 / iOS P7).
//  Ported from Android's TimeSheetViewModel.kt `loadMyHours` / `MyHoursState` and TimeSheetApp.kt
//  `MyHoursScreen` / `myHoursStatusRes` at 60f6886 (TASK-189, since 2026-08-24). Read those first;
//  every clause below is one of theirs.
//
//  WHY IT EXISTS. History is the phone's own log of what it wrote, so an admin's correction, a shift
//  taken on another device or one the office closed is invisible there. This is the one screen that
//  answers "what did the office record for me?" - and ONLY that: no total, no rate, no euro amount,
//  no control that writes a shift (decision-19 / 47: it is read-only about the past, full stop).
//
//  READ-ONLY AND NEVER CACHED, structurally rather than by promise:
//    - the state is a value in a store the SCREEN owns; popping the screen drops it, and the next
//      entry asks the server again. Nothing here touches SwiftData, UserDefaults or a file
//      (checks/my-hours-check.swift fails if it does);
//    - the request goes through LoadGuard (P4): a newer request, a change of worker, a sign-out or a
//      cancel DROPS the answer, so B never sees A's hours, not even for the frame it takes to arrive
//      (and a cancelled request is dropped before API.swift's `send` can turn it into "offline");
//    - GET /shifts/mine answers for the SESSION's worker and nobody else (decision-22): the call
//      takes no worker id and must never gain one.
//
//  THE FAILURES (`MyHoursState.after(failure:)`, and the words are the screen's):
//    - status 0, the request never got an answer  -> offline sentence + Refresh
//    - 401                                         -> NOTHING: API.swift's choke point has already
//      posted .sessionRejected and the app is signing out; "could not be loaded" on the way out
//      would be a lie about why (Android: 401 never shows here). The state stays `.loading`.
//    - any other failure, a body this build cannot read -> the generic sentence + Refresh
//  The wire decode is STRICT, like the migration's: one row this build cannot read fails the whole
//  list into the generic sentence. A silently shorter list of somebody's hours would be worse.
//
//  FOUNDATION + OBSERVATION, no UI, on purpose: checks/my-hours-check.swift runs this file on a Mac
//  (it needs Branding, TagLink, API, WorkerScope, LoadGuard and ViennaTime cat-ed in front). The
//  screen that draws it is MyHoursView.swift.
//

import Foundation
import Observation

enum MyHours {

    // MARK: The window

    /// Android: `Instant.now().minusSeconds(60 * 86_400L)` - "the current and prior payroll period
    /// without a date picker".
    static let windowDays = 60
    static let window: TimeInterval = TimeInterval(windowDays) * 86_400

    /// `since` is REQUIRED by the server (400 without it) and is the caller's choice.
    static func since(now: Date) -> Date { now.addingTimeInterval(-window) }

    // MARK: A row

    /// The one thing this screen exists to say honestly. THE ORDER MATTERS and is Android's
    /// `myHoursStatusRes`: no end time is checked FIRST, so a running shift (which by construction
    /// has no correction and no auto-close) can never fall into another branch.
    /// `correctedAt` is only ever set by the server on a row that WAS auto-closed (resolve 409s
    /// otherwise), so the third branch is unambiguous. `closed` is the one case ShiftRow draws as
    /// a blank pill today.
    enum Status: Equatable {
        case running
        case autoClosed
        case corrected
        case closed
    }

    static func status(of shift: WireShift) -> Status {
        if shift.endTime == nil { return .running }
        if shift.needsResolution { return .autoClosed }
        if shift.correctedAt != nil { return .corrected }
        return .closed
    }

    /// What one row shows. Dates stay `Date`s: the VIEW formats them in Vienna (ViennaTime), so the
    /// check can run the formatting against any device zone.
    struct Row: Equatable, Identifiable {
        let id: Int
        /// The BUILDING (`location_name`: a shift stores `place.location_id`). nil -> "Unknown location".
        let building: String?
        let status: Status
        /// decision-56 section 5: a manual half is never indistinguishable from a tapped one.
        let manual: Bool
        let start: Date
        /// nil = no end yet. Never rendered as zero and never as a made-up time.
        let end: Date?

        /// OMITTED - not zero, not fake - for the running row, the only case with no end (Android).
        var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
    }

    static func row(from shift: WireShift) -> Row {
        Row(id: shift.id,
            building: shift.locationName,
            status: status(of: shift),
            manual: (shift.manualStart ?? false) || (shift.manualClose ?? false),
            start: shift.startTime,
            end: shift.endTime)
    }
}

// MARK: - State

enum MyHoursState: Equatable {
    /// Nothing known yet, or a fresh request is in flight. The previous list is DROPPED while it
    /// loads (as Android does): a stale row next to a spinner is a wrong list.
    case loading
    case loaded([MyHours.Row])
    /// `offline` is "the request never got an answer" (status 0) and nothing else.
    case failed(offline: Bool)
}

extension MyHoursState {
    /// How one failed request reads, or nil when it must read as NOTHING (a 401: see the header).
    static func after(failure error: Error) -> MyHoursState? {
        guard let failure = error as? APIFailure else { return .failed(offline: false) }
        if failure.status == 401 { return nil }
        return .failed(offline: failure.status == 0)
    }
}

// MARK: - Store

@MainActor
@Observable
final class MyHoursStore {
    private(set) var state: MyHoursState = .loading

    @ObservationIgnored private var loadGuard = LoadGuard()
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    private let fetch: (Date) async throws -> [WireShift]
    private let now: () -> Date

    /// - Parameters:
    ///   - fetch: injectable so the check can answer slowly, wrongly or never; the app passes
    ///     nothing and gets GET /shifts/mine?since=.
    ///   - now: injectable so the window is checked from a fixed instant.
    init(fetch: @escaping (Date) async throws -> [WireShift] = { since in try await ShiftAPI.mine(since: since) },
         now: @escaping () -> Date = { .now }) {
        self.fetch = fetch
        self.now = now
    }

    /// Ask the server for THIS worker's last 60 days. Returns immediately; the answer arrives in
    /// `state`. A NO-OP unless `workerId` still holds the session (Android: `if (_session.value !is
    /// SignedIn) return`). Otherwise it supersedes any request in flight, sets `.loading` FIRST (the
    /// previous list is dropped), and publishes only if, when the answer lands, this is still the
    /// latest request, the worker still holds the session, and the task was not cancelled.
    ///
    /// - Parameter session: the session's worker id RIGHT NOW, asked again after the await.
    /// - Returns: the task, for the check to await. The app discards it.
    @discardableResult
    func load(for workerId: Int, session: @escaping @MainActor () -> Int?) -> Task<Void, Never>? {
        guard WorkerScope.isCurrent(workerId, session: session()) else { return nil }
        inFlight?.cancel()
        let ticket = loadGuard.begin(for: workerId)
        state = .loading
        let since = MyHours.since(now: now())
        let fetch = fetch
        let task = Task { [weak self] in
            let next: MyHoursState?
            do {
                next = .loaded(try await fetch(since).map(MyHours.row(from:)))
            } catch {
                next = MyHoursState.after(failure: error)
            }
            guard let self, let next else { return }
            self.publish(next, ticket: ticket, session: session(), cancelled: Task.isCancelled)
        }
        inFlight = task
        return task
    }

    /// The screen went away: drop the request in flight. A cancelled request publishes nothing.
    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func publish(_ next: MyHoursState, ticket: LoadGuard.Ticket, session: Int?, cancelled: Bool) {
        guard loadGuard.accepts(ticket, sessionWorkerId: session, cancelled: cancelled) else { return }
        state = next
    }
}
