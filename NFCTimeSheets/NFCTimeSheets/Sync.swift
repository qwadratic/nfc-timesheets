//
//  Sync.swift
//  NFCTimeSheets
//
//  The glue between the local SwiftData queue and the two-halves shift API
//  (decision-19). Everything here is @MainActor: the store is small (a handful of
//  workers, a few hundred rows a year) and a background context would buy nothing but
//  concurrency bugs.
//

import Foundation
import SwiftData

// MARK: - Roster

/// Drop what the picker era left behind: the self-chosen worker id/name, and the cached
/// list of every colleague's name. Nothing reads these any more (decision-22), but they
/// sit in the app's defaults plist - and in its backups - until something deletes them.
/// `session.appleUserId` joins the list for the same reason (decision-50): Sign in with
/// Apple is retired from this screen, and Auth.swift no longer writes or reads that key.
/// One upgrade does it; the keys are dead and will never be written again.
func purgeLegacyIdentityDefaults() {
    for key in ["workerId", "workerName", "rosterWorkersV2", "rosterWorkers", "session.appleUserId"] {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// GET /roster -> cache locations in SwiftData.
///
/// The worker list that used to be cached here fed the Settings picker, and the picker
/// is gone (decision-22): the app no longer needs to know who ELSE exists, only who the
/// server says the holder of this session is. Caching a staff list on every phone was a
/// small leak with no remaining purpose, so it is not cached at all.
@MainActor
func refreshRoster(context: ModelContext) async {
    guard let roster = try? await RosterAPI.fetch() else { return }

    let existing = (try? context.fetch(FetchDescriptor<Site>())) ?? []
    let wanted = Set(roster.locations.map(\.id))
    for location in roster.locations {
        if let site = existing.first(where: { $0.locationId == location.id }) {
            site.name = location.name
            site.slug = location.slug
        } else {
            context.insert(Site(locationId: location.id, slug: location.slug, name: location.name))
        }
    }
    // Locations that are gone (or, on the first launch after this version, the stale
    // hardware-UID rows the old build cached) drop out.
    for site in existing where !wanted.contains(site.locationId) { context.delete(site) }
    try? context.save()
    // The zones of the same answer (decision-43). Only reached on a SUCCESSFUL fetch (the
    // guard above returns first), so a phone with no signal keeps the last zones it had.
    RosterZones.shared.replace(with: roster.zones)
}

// MARK: - Feature flags

/// GET /flags -> cache in UserDefaults (decision-57).
///
/// Fetched on the same pass as the roster, and FAILS SILENTLY on purpose: a flag is
/// decoration, so a server that is unreachable - or old enough not to serve /flags at all -
/// leaves the last cached answer standing and the app keeps working exactly as before.
func refreshFlags() async {
    guard let flags = try? await FlagsAPI.fetch() else { return }
    FeatureFlags.store(flags)
}

// MARK: - Shift sync

/// Push every local shift the server has not acknowledged yet.
///
/// ponytail: called on tap, on pull-to-refresh and when the Log tab appears - there is
/// no background retry. CEILING: a shift taken with no signal sits on the phone until
/// the app is next opened. Fine for a crew that opens the app twice a day anyway.
/// UPGRADE PATH: BGAppRefreshTask, once someone actually gets bitten.
///
/// Order matters: oldest first, and for each shift OPEN before CLOSE. The server allows
/// one open shift per worker, so a newer open would 409 until the older one is closed.
///
/// `workerId` is the SESSION's worker, and rows belonging to anyone else are refused
/// rather than sent: the server now attributes a shift to whoever holds the cookie, so
/// posting worker A's queued row while worker B is signed in would file A's hours under
/// B's name. That is the exact hole decision-22 closes, re-opened from the client side.
@MainActor
func syncPending(context: ModelContext, workerId: Int) async {
    let all = (try? context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor<Shift>(\.startTime)]))) ?? []
    // THE ONE PREDICATE (PendingWork.state): the delivery summary on the idle list, the running screen
    // and the sign-in screen counts exactly these rows, so what is tried and what is said cannot drift.
    // It is `!syncBlocked && (!isFullySynced || a finish is owed with its proof)`, spelled once.
    for shift in all where PendingWork.state(of: shift.deliveryRow()) == .waiting {
        if shift.openSyncedAt == nil {
            guard await pushOpen(shift, as: workerId) else { continue }  // don't close what never opened
        }
        // `pendingEvidenceEnd` is the finish time a proof-of-work close was sent with (shift
        // evidence): while it is set the close is still owed, even though the row's own endTime
        // may not be written yet. The "another account's row" guard is INSIDE pushClose
        // (TASK-365.4), so it is one rule in one place.
        if let end = shift.pendingEvidenceEnd ?? shift.endTime, shift.closeSyncedAt == nil {
            await pushClose(shift, end: end, as: workerId)
        }
    }
    try? context.save()
}

/// - Returns: true when the server now holds this shift as open.
@MainActor
private func pushOpen(_ shift: Shift, as workerId: Int) async -> Bool {
    guard TagLink.normalizedUUID(shift.locationId) != nil else {
        // A row from before this version, or a tag that never parsed. It can never be
        // posted, so say so once and stop retrying it forever.
        shift.syncBlocked = true
        shift.syncError = String(localized: "This shift is missing its location and can't be sent.")
        return false
    }
    guard shift.workerId == workerId else {
        // Queued by a different worker on this phone (or by a build old enough to have
        // no worker at all). The server would happily file it under whoever is signed in
        // now, so it is blocked LOUDLY instead - a wrong name on a payslip is worse than
        // a visible failure.
        shift.syncBlocked = true
        shift.syncError = String(localized: "This shift was logged by a different account and can't be sent.")
        return false
    }
    do {
        // "A push was tried, now" - BEFORE the request, for both outcomes (PendingWork.swift:
        // DeliveryAttempt). The only reader is the delivery details sheet's "Last attempt".
        DeliveryAttempt.stamp()
        shift.lastAttemptAt = .now
        let envelope = try await ShiftFlowAPI.open(clientUuid: shift.clientUuidString,
                                                   locationId: shift.locationId,
                                                   startTime: shift.startTime,
                                                   manual: shift.manualStart)
        apply(envelope.shift, to: shift)
        shift.openSyncedAt = .now
        shift.syncError = nil
        return true
    } catch let failure as APIFailure {
        record(failure, on: shift)
        return false
    } catch {
        shift.syncError = APIFailure(status: 0, code: "network").workerMessage
        return false
    }
}

@MainActor
private func pushClose(_ shift: Shift, end: Date, as workerId: Int) async {
    // ANOTHER ACCOUNT'S CLOSE STAYS ON THE PHONE. The server looks the shift up under whoever holds
    // the cookie (decision-22), so worker A's finished-but-unsent row, pushed while B is signed in,
    // answers 404 unknown_shift - which is terminal, so it would BLOCK A's row for ever and A's
    // shift would sit open on the server until the 8h timer closed it. Skipping changes nothing on
    // the row: no error, no block, no request. It is simply still pending when A signs back in,
    // and goes out then. (pushOpen's wrong-account block is a separate, deliberately untouched
    // behaviour - same as Android's SyncPlan.)
    guard shift.workerId == workerId else { return }
    do {
        DeliveryAttempt.stamp()   // before the request, like pushOpen's
        shift.lastAttemptAt = .now
        // Carry the local flag up. The server only ever raises auto_closed, never clears it,
        // so a plain tap-out cannot downgrade a shift the 8h timer already flagged.
        // `manual` rides up the same way `autoClosed` does, from the local row, so a Stop
        // pressed with no signal still lands flagged when the queue drains hours later.
        let envelope = try await ShiftFlowAPI.close(clientUuid: shift.clientUuidString,
                                                    endTime: end,
                                                    autoClosed: shift.pendingEvidenceEnd != nil ? shift.pendingEvidenceAuto : shift.autoClosed,
                                                    manual: shift.pendingEvidenceEnd != nil ? shift.pendingEvidenceManual : shift.manualClose, proofId: shift.proofId)
        // The server's row wins. If the 8h timer got there first this comes back with
        // auto_closed = true and corrected_at = null, and the worker is routed to the
        // resolution sheet: closing does NOT silently resolve a timer-closed shift.
        apply(envelope.shift, to: shift)
        shift.pendingEvidenceEnd = nil
        shift.closeSyncedAt = .now
        shift.syncError = nil
    } catch let failure as APIFailure {
        record(failure, on: shift)
    } catch {
        shift.syncError = APIFailure(status: 0, code: "network").workerMessage
    }
}

/// What the delivery summary needs of a row (PendingWork.swift), as a value - the one mapping from
/// the SwiftData model, so the engine above and the screens count with the same fields.
///
/// `sessionWorkerId` is the worker the server says holds this session, or nil when nobody does (the
/// sign-in screen). It only feeds `queuedByAnotherAccount`, which only the wording reads.
extension Shift {
    func deliveryRow(sessionWorkerId: Int? = nil) -> PendingRow {
        PendingRow(startTime: startTime,
                   openSyncedAt: openSyncedAt,
                   closeSyncedAt: closeSyncedAt,
                   isOpen: isOpen,
                   syncBlocked: syncBlocked,
                   finishOwed: pendingEvidenceEnd != nil,
                   queuedByAnotherAccount: sessionWorkerId.map { $0 != workerId } ?? false,
                   lastChangedAt: pendingEvidenceEnd ?? endTime ?? startTime)
    }
}

/// Copy the server's version of the row over the local one.
@MainActor
private func apply(_ wire: WireShift, to shift: Shift) {
    shift.serverId = wire.id
    shift.locationIntervalSeconds = wire.locationIntervalSeconds ?? 0
    shift.proofOfWorkRequired = wire.proofOfWorkRequired ?? false
    // ONLY UPWARDS, both close flags. This is called with the OPEN's answer (pushOpen) as well as
    // the close's, and an open answers false for both. A phone that was offline when the worker
    // finished without a tag, or walked to another building, holds a LOCAL true that pushClose has
    // not read yet; assigning the open's false over it sent the close up unflagged
    // (TASK-365.22 D1: manual_close=false, and decision-10's "no shift reaches payroll with an
    // unconfirmed end" bypassed). The server itself only ever raises auto_closed, so OR matches it.
    shift.autoClosed = shift.autoClosed || wire.autoClosed
    shift.correctedAt = wire.correctedAt
    // Same rule for the manual flags, and a build talking to a server that has not shipped
    // decision-56's migration yet gets nil back: `?? false` there keeps the local truth instead of
    // quietly un-flagging a manual row the worker really did create.
    shift.manualStart = wire.manualStart ?? shift.manualStart
    shift.manualClose = shift.manualClose || (wire.manualClose ?? false)
    if let end = wire.endTime { shift.endTime = end }
}

/// A failure ALWAYS leaves a message on the row. The old code caught 400s into a bare
/// `catch {}`, which left syncError nil, the row looking fine and the shift retrying for
/// ever - a data-loss bug wearing a clean UI.
@MainActor
private func record(_ failure: APIFailure, on shift: Shift) {
    if ["proof_required", "proof_expired"].contains(failure.code) {
        // The server refused this close for want of a photo, so the row goes back to what it was
        // BEFORE the close was attempted - all of it. A tap-out or a manual stop (and a switch's
        // walk-away flag) writes `autoClosed` / `manualClose` together with the end time; left
        // behind, an open row that reads `autoClosed` is drawn as "closed automatically" instead of
        // a running clock, and a later tap-out would go up flagged manual. Reachable since a finish
        // whose policy the phone does not know yet runs local-first (ContentView.prepareCompletion).
        shift.endTime = nil
        shift.autoClosed = false
        shift.manualClose = false
        shift.proofId = nil
        shift.pendingEvidenceEnd = nil
        shift.proofOfWorkRequired = true
        shift.syncBlocked = false
        shift.syncError = failure.workerMessage
        return
    }
    shift.syncError = failure.workerMessage
    shift.syncBlocked = !failure.isRetryable
    // The one place every rejection passes through, so this is the one place it has to be
    // reported from. `ts.api.code` is the server's own error code, which is what makes a
    // failed clock-in diagnosable without reading this file.
    Telemetry.log("shift sync rejected", .error, [
        "ts.api.status": failure.status,
        "ts.api.code": failure.code,
        "ts.sync.blocked": !failure.isRetryable,
        "ts.shift.client_uuid": shift.clientUuidString,
        "ts.location.id": shift.locationId,
    ])
}

// MARK: - Server-authoritative reconciliation

/// Adopt an open shift the server knows about but this phone does not: app reinstalled,
/// second device, or a background tap that opened the shift before the store was written.
/// Without this the worker would tap out and get 404 unknown_shift for ever.
///
/// No worker argument: GET /shifts/open answers for the session's worker and nobody
/// else (decision-22), so the row that comes back is by construction ours.
@MainActor
func adoptServerOpenShift(context: ModelContext) async {
    guard let remote = try? await ShiftAPI.currentOpen() else { return }
    guard let key = remote.clientUuid.flatMap({ UUID(uuidString: $0) }) else { return }

    let known = (try? context.fetch(FetchDescriptor<Shift>())) ?? []
    if let existing = known.first(where: { $0.clientUuid == key }) {
        existing.locationIntervalSeconds = remote.locationIntervalSeconds ?? 0
        existing.proofOfWorkRequired = remote.proofOfWorkRequired ?? false
        try? context.save()
        return
    }

    let local = Shift(workerId: remote.workerId,
                      workerName: "",
                      locationId: remote.locationId,
                      startTime: remote.startTime)
    local.clientUuid = key
    local.locationIntervalSeconds = remote.locationIntervalSeconds ?? 0
    local.proofOfWorkRequired = remote.proofOfWorkRequired ?? false
    local.serverId = remote.id
    local.openSyncedAt = .now
    local.autoClosed = remote.autoClosed
    local.correctedAt = remote.correctedAt
    local.manualStart = remote.manualStart ?? false
    local.manualClose = remote.manualClose ?? false
    context.insert(local)
    try? context.save()
}

/// Shifts the 8h timer closed that no human has fixed yet (decision-10), for the
/// session's worker.
func fetchUnresolved() async -> [WireShift] {
    (try? await ShiftAPI.unresolved()) ?? []
}

/// POST /shifts/:id/resolve, then mirror the result locally.
@MainActor
func resolveShift(context: ModelContext, shift: WireShift, end: Date, proofId: String? = nil) async -> String? {
    do {
        let updated = try await ShiftAPI.resolve(shiftId: shift.id, endTime: end, proofId: proofId)
        if let key = updated.clientUuid.flatMap({ UUID(uuidString: $0) }),
           let local = ((try? context.fetch(FetchDescriptor<Shift>())) ?? [])
               .first(where: { $0.clientUuid == key })
        {
            local.endTime = updated.endTime
            local.autoClosed = updated.autoClosed
            local.correctedAt = updated.correctedAt
            local.closeSyncedAt = .now
            local.syncError = nil
            local.syncBlocked = false
            try? context.save()
        }
        return nil
    } catch let failure as APIFailure {
        return failure.workerMessage
    } catch {
        return APIFailure(status: 0, code: "network").workerMessage
    }
}
