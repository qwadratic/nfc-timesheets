//
//  ScheduleStore.swift
//  NFCTimeSheets
//
//  THE WORKER'S PLANNED ASSIGNMENTS, IN MEMORY, FOR THE SCREEN AND FOR NOTHING ELSE
//  (decision-80). Ported from android/.../ui/TimeSheetViewModel.kt `loadSchedule()` and the
//  `ScheduleState` beside it; read that function first, every clause below is one of its.
//
//  DISPLAY ONLY, and that is a structural property, not a promise:
//
//    - It is held as @State in LogView and dies with it: on sign-out, on a 401 and, through P3's
//      `.id(worker.id)` on the TabView, on a change of worker. It is NOT a SwiftData model, is
//      never written to disk, and is not covered by decision-62's invalidation because there is
//      nothing to invalidate - every appearance of the shift screen asks the server again.
//    - Nothing on the tap path, the sync pass, `refresh()`, the shift signals or navigation
//      reads it, awaits it or waits for it. `load` returns at once; the request runs in its OWN
//      unstructured Task, concurrent with and never inside the roster / sync pass. A schedule
//      that is slow, failing or missing on the server (production without migration 025 answers
//      404 / 500) can therefore never delay or fail a clock-in. checks/schedule-check.swift
//      reads ContentView.swift, Sync.swift and the signal files as text and fails if that
//      stops being true.
//
//  WHY AN UNSTRUCTURED Task AND NOT `.task`: API.swift's `send` converts EVERY URLSession error,
//  a cancelled one included, into `APIFailure(status: 0)`. A `.task` cancelled by leaving the tab
//  would therefore publish "could not load without a connection" on a phone with full signal.
//  Here a cancelled request is dropped before it can write anything (LoadGuard.accepts takes
//  `cancelled:`), and a superseded one is cancelled outright.
//
//  What the screen shows for each state is ScheduleViews.swift's business. What each FAILURE
//  becomes is decided once, below, in `ScheduleState.after(failure:)`.
//

import Foundation
import Observation

/// What the schedule surfaces render. Equatable so a card can reset its own toggle when the
/// state changes (Android `remember(state)`).
enum ScheduleState: Equatable {
    /// Nothing known yet, or a fresh request is in flight. The previous list is DROPPED while it
    /// loads (as Android does): a stale row on screen next to a spinner is a wrong plan.
    case loading
    case loaded([WireScheduleAssignment])
    /// `offline` is "the request never got an answer" (status 0) and nothing else. Every other
    /// failure - 404 and 500 from a server without the route, a body this build cannot read - is
    /// the generic one.
    case failed(offline: Bool)
}

extension ScheduleState {
    /// How one failed request reads, or nil when it must read as NOTHING.
    ///
    /// - APIFailure(status 0): offline.
    /// - APIFailure(401): nil. Every 401 that is not `invalid_code` already posted
    ///   `.sessionRejected` from API.swift's choke point and the app is signing out; the card is
    ///   about to be torn down, and a flash of "could not load" on the way out would be a lie
    ///   about why (Android: "401 never shows here"). The state stays `.loading`.
    /// - Any other APIFailure, a DecodingError, anything else: generic.
    ///
    /// Deliberately NOT `workerMessage`: that is the clock-in vocabulary ("Server trouble - will
    /// retry"), which promises a retry nothing here will do.
    static func after(failure error: Error) -> ScheduleState? {
        guard let failure = error as? APIFailure else { return .failed(offline: false) }
        if failure.status == 401 { return nil }
        return .failed(offline: failure.status == 0)
    }
}

@MainActor
@Observable
final class ScheduleStore {
    private(set) var state: ScheduleState = .loading

    @ObservationIgnored private var loadGuard = LoadGuard()
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    private let fetch: () async throws -> [WireScheduleAssignment]

    /// - Parameter fetch: injectable so the check can answer slowly, wrongly or never; the app
    ///   passes nothing and gets GET /me/schedule.
    init(fetch: @escaping () async throws -> [WireScheduleAssignment] = { try await ScheduleAPI.mine() }) {
        self.fetch = fetch
    }

    /// Ask the server for this worker's plan. Returns immediately; the answer arrives in `state`.
    ///
    /// A NO-OP unless `workerId` still holds the session (Android: `if (_session.value !is
    /// SignedIn) return`). Otherwise it supersedes any request in flight, sets `.loading` FIRST
    /// (the previous list is dropped), and publishes only if, when the answer lands, this is still
    /// the latest request, the worker still holds the session, and the task was not cancelled.
    ///
    /// - Parameter session: the session's worker id RIGHT NOW, asked again after the await.
    /// - Returns: the task, for the check to await. The app discards it.
    @discardableResult
    func load(for workerId: Int, session: @escaping @MainActor () -> Int?) -> Task<Void, Never>? {
        guard WorkerScope.isCurrent(workerId, session: session()) else { return nil }
        inFlight?.cancel()
        let ticket = loadGuard.begin(for: workerId)
        state = .loading
        let fetch = fetch
        let task = Task { [weak self] in
            let next: ScheduleState?
            do {
                next = .loaded(try await fetch())
            } catch {
                next = ScheduleState.after(failure: error)
            }
            guard let self, let next else { return }
            self.publish(next, ticket: ticket, session: session(), cancelled: Task.isCancelled)
        }
        inFlight = task
        return task
    }

    private func publish(_ next: ScheduleState, ticket: LoadGuard.Ticket, session: Int?, cancelled: Bool) {
        guard loadGuard.accepts(ticket, sessionWorkerId: session, cancelled: cancelled) else { return }
        state = next
    }
}
