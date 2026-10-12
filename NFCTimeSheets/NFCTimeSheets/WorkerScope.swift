//
//  WorkerScope.swift
//  NFCTimeSheets
//
//  WHOSE ROWS ARE THESE. The SwiftData store holds every shift this PHONE ever queued, for
//  every account that ever signed in on it - it is a device-wide outbox, and it has to be:
//  worker A's unsent hours must survive worker B signing in, and go out when A comes back
//  (Android keeps the outbox and the pending summary device-wide for the same reason,
//  ShiftStore.kt). What is NOT device-wide is what a SCREEN shows and what a TAP toggles:
//  those belong to the worker the server says holds this session.
//
//  Before this file every read in the app was unscoped. On a shared phone B saw A's Recent,
//  History and totals, could swipe-delete A's rows, got A's running screen, tab lock,
//  reminders and material context if A left a shift open, and B's first tap CLOSED A's row
//  (or auto-closed it as a walk-away) and the close went out under B's cookie, where the
//  server answered 404 unknown_shift (it attributes by session, decision-22).
//
//  ONE HELPER, and every read site goes through it - checks/worker-scope-check.swift reads
//  ContentView.swift and MaterialsView.swift as text and fails on any `@Query` over Shift
//  that is not named `allShifts`, on any use of `allShifts` that does not go through
//  forWorker / openShift(for:) / completed(for:), and on a raw `.isOpen` read. One missed
//  read site is a cross-worker toggle, which is why that check exists.
//
//  FOREIGN ROWS ARE KEPT. Nothing here deletes, edits or hides a row from the SYNC engine:
//  syncPending iterates ALL rows on purpose, and so does the delivery summary (PendingWork.swift,
//  P6): the DEVICE-WIDE read has exactly one name here, `deviceWide()`, so that "this screen reads
//  everybody's rows" is a loud, greppable decision and never an accident. checks/worker-scope-check.swift
//  allows it in ContentView.swift only as the input of that summary.
//
//  LEGACY ROWS (workerId 0, from before identity came from the session) belong to nobody and
//  are therefore listed for nobody: `owns` requires a real session id, so no id can ever
//  match a 0. DataMigrations archives most of them (and MigrationReceipt showed the worker
//  once what happened); the few it keeps are blocked rows with no attributable owner, and a
//  worker must neither see them in History nor be able to swipe-delete them.
//
//  FOUNDATION-ONLY ON PURPOSE (like TagLink / ShiftSignal / Zones): the `Shift` @Model
//  conforms to WorkerScoped over in NFCTimeSheetsApp.swift, and the check runs this file with
//  a plain struct standing in for it.
//

import Foundation

/// The three facts about a row that scoping needs. `Shift` already has all three, by these
/// names, so its conformance is an empty extension.
protocol WorkerScoped {
    var workerId: Int { get }
    var startTime: Date { get }
    var endTime: Date? { get }
}

enum WorkerScope {
    /// Does a row written under `rowWorkerId` belong to the session's worker?
    ///
    /// A session id is the server's, always > 0. Requiring it means a legacy row (workerId 0)
    /// can never match, whatever ends up being passed in.
    static func owns(_ sessionWorkerId: Int, row rowWorkerId: Int) -> Bool {
        sessionWorkerId > 0 && rowWorkerId == sessionWorkerId
    }

    /// Is the worker a screen was built for still the one holding the session? Asked AFTER an
    /// `await`, before publishing: a refresh that started for A and finishes after A signed
    /// out (or was replaced by B) must not re-arm A's badge over B's, nor over nobody's.
    /// Android re-checks the worker id after every async read for the same reason
    /// (TimeSheetViewModel.refresh).
    static func isCurrent(_ viewWorkerId: Int, session sessionWorkerId: Int?) -> Bool {
        sessionWorkerId == viewWorkerId
    }
}

extension Sequence where Element: WorkerScoped {
    /// This worker's rows, in the order the sequence already had them.
    func forWorker(_ id: Int) -> [Element] {
        filter { WorkerScope.owns(id, row: $0.workerId) }
    }

    /// The row a tap toggles: this worker's NEWEST open row, or nil. Never another worker's -
    /// B's tap must start B's own shift, not close A's (Android ShiftStore.openShift).
    func openShift(for id: Int) -> Element? {
        forWorker(id).filter { $0.endTime == nil }.max { $0.startTime < $1.startTime }
    }

    /// This worker's finished rows, in the order the sequence already had them.
    func completed(for id: Int) -> [Element] {
        forWorker(id).filter { $0.endTime != nil }
    }

    /// EVERY account's rows - the phone's outbox - in the order the sequence already had them.
    /// The ONE unscoped read a screen may make, and it has ONE legitimate reader: the delivery
    /// summary (PendingWork.swift), which counts what the phone still holds for whoever queued it,
    /// including on the sign-in screen where nobody is signed in. It is never the source of a list, a
    /// total, a tab lock or a tap's toggle. Nothing is filtered, hidden or deleted.
    func deviceWide() -> [Element] {
        Array(self)
    }
}
