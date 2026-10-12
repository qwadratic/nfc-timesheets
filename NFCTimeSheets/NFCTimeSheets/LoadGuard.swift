//
//  LoadGuard.swift
//  NFCTimeSheets
//
//  WHICH ANSWER MAY STILL BE SHOWN. A screen that loads something over the network asks the
//  same question every time the answer comes back: "is this still the answer to what is on
//  screen?" Three things make it no longer so, and each has already burned somebody:
//
//    - a NEWER request was started (the worker left the tab and came back, tapped the refresh
//      icon twice) and a slow older answer lands after it and overwrites it;
//    - the worker CHANGED or signed out while the request was in flight (a shared phone: B must
//      never see A's list, not even for the frame it takes to arrive);
//    - the request was CANCELLED. API.swift's `send` turns every URLSession error, a cancelled
//      task included, into `APIFailure(status: 0)`, which reads as "offline" - so a cancelled
//      request would paint "no connection" on a phone with perfect signal.
//
//  Android answers all three with one counter bumped on every request / sign-out / 401 / worker
//  change, compared after the await together with "still signed in" (TimeSheetViewModel
//  `scheduleRequest`, loadSchedule). This is that counter, plus the worker it was issued for,
//  as a value type with nothing in it but arithmetic, so checks/schedule-check.swift can run
//  every rule without a screen.
//
//  FOUNDATION-ONLY ON PURPOSE, and it needs WorkerScope.swift in front of it (the one place the
//  app's notion of "the worker who still holds the session" is written down - P3). It is
//  written to be reused by the next screen that loads over the network (P7's My hours): nothing
//  in it knows what is being loaded.
//
//  USE:
//      var loadGuard = LoadGuard()
//      let ticket = loadGuard.begin(for: worker.id)      // supersedes every earlier ticket
//      ...await the network...
//      if loadGuard.accepts(ticket, sessionWorkerId: session.worker?.id, cancelled: Task.isCancelled) {
//          publish(answer)
//      }
//

import Foundation

struct LoadGuard {
    /// What a request carries away with it: which request it was, and for whom.
    struct Ticket: Equatable {
        let generation: Int
        let workerId: Int
    }

    /// Bumped by every `begin` and by every change of worker. Monotonic, never reused.
    private(set) var generation = 0
    /// The worker the last `begin` / `adopt` was for. nil until something has been started.
    private(set) var workerId: Int?

    /// Android `adopt()`: a DIFFERENT worker supersedes everything in flight and returns true -
    /// the caller must drop whatever it was showing. The SAME worker is left alone and returns
    /// false: confirming a cached session must not strand a screen that already has its answer.
    @discardableResult
    mutating func adopt(_ id: Int) -> Bool {
        guard workerId != id else { return false }
        generation += 1
        workerId = id
        return true
    }

    /// Start a request for `id`. Every earlier ticket, for this worker or another, is stale from
    /// this moment on.
    mutating func begin(for id: Int) -> Ticket {
        adopt(id)
        generation += 1
        return Ticket(generation: generation, workerId: id)
    }

    /// May the answer to `ticket` be published? Only if ALL of: it is still the latest request,
    /// the worker it was issued for still holds the session (WorkerScope.isCurrent: false for
    /// another worker AND for nobody - a signed-out phone shows nothing), and its task was not
    /// cancelled.
    func accepts(_ ticket: Ticket, sessionWorkerId: Int?, cancelled: Bool) -> Bool {
        !cancelled
            && ticket.generation == generation
            && WorkerScope.isCurrent(ticket.workerId, session: sessionWorkerId)
    }
}
