// Runnable check: what the phone still holds, said in words (TASK-365.7, iOS P6, decision-82).
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/PendingWork.swift checks/pending-work-check.swift \
//     > /tmp/pending-work-check.swift && swift /tmp/pending-work-check.swift
//
// WHAT THE FEATURE IS: unsent and refused shifts stay visible as up to two tappable count rows on the
// idle list, the running screen and the SIGN-IN screen, and open a details sheet with ONE
// state-specific sentence, the earliest start and the last attempt. Ported from Android at 60f6886
// (core/PendingWork.kt, ui/DeliveryStatus.kt; android/checks/core-check.kt:2617-2710 is the twin of
// parts 1 and 2). iOS has NO background delivery, so nothing here may promise one.
//
// WHAT THIS CHECK GUARDS, in five parts (plus the grace, 1b), because each one is a way this would quietly mislead:
//   1. THE COUNT, run for real: an empty queue is nothing; a not-yet-opened row waits; an open
//      shift whose OPEN landed is NOT pending (and neither is one a 422 proof_required reopened);
//      a closed fully-synced row is not; open-synced-but-close-unsent waits; a finish owed with a
//      proof waits; blocked is counted separately and never folded into waiting; the earliest start
//      spans both; and `state(of:)` equals the old inline filter of syncPending over EVERY
//      combination of the five inputs - the structural guarantee that "what the engine will try" and
//      "what the screen says" are one predicate.
//   2. THE LAST ATTEMPT: never invented, never older than the row it is shown for.
//   3. THE WORDS: exactly one waiting sentence, signed-out or all-foreign -> sign in, otherwise
//      "open the app" - never an automatic-delivery promise.
//   4. THE WIRING, read as text: the engine iterates the same predicate; the stamp sits after the
//      guards and before the request; the views draw nothing when empty, carry no surface, read no
//      store, are placed where the plan says, are fed device-wide only through WorkerScope, and are
//      read by NO tap, sync, signal or navigation code.
//   5. THE STRINGS: both languages, the exact keys, German = Android's verbatim (one named
//      exception), real one/other plurals, and not a single string on this surface that says
//      "automatically" or mentions force-stopping.
//
// DEVIATION FROM ANDROID, documented where it matters: LAST ATTEMPT is one global date in
// UserDefaults (DeliveryAttempt), not Shift.lastAttemptAt per row - a SwiftData column risks the
// unpushed-shift store (a failed lightweight migration is a fatalError at launch). The guard in part
// 2 is what keeps a global value honest.
//
// WHAT THIS CANNOT PIN: that the rows look right, that the sheet reads at 200% Dynamic Type, that
// a tap in a List row opens the sheet instead of the row, that VoiceOver reads the count. Those need
// a worker session on a device or simulator (TASK-365.22 is the rig that signs one in).
//
// RED CASES, reproduced against mutated copies of the real files before this was trusted: see the
// commit that added it.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // fixed, so nothing depends on "now"
func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

/// A row, defaulting to the most common shape: opened and closed on the phone, nothing sent.
func row(start: Double = 0, open: Double? = nil, close: Double? = nil, isOpen: Bool = false,
         blocked: Bool = false, owed: Bool = false, other: Bool = false) -> PendingRow {
    PendingRow(startTime: at(start), openSyncedAt: open.map(at), closeSyncedAt: close.map(at), isOpen: isOpen,
               syncBlocked: blocked, finishOwed: owed, queuedByAnotherAccount: other)
}

// ---------------------------------------------------------------------------------
// 1. The count
// ---------------------------------------------------------------------------------

check(PendingWork.summarise([], lastAttemptAt: nil) == PendingWork.nothing, "an empty queue is nothing pending")
check(PendingWork.nothing.isEmpty && PendingWork.nothing.total == 0, "nothing is empty and totals zero")
check(PendingWork.summarise([], lastAttemptAt: at(500)) == PendingWork.nothing,
      "an empty queue reports no last attempt either, whatever the global stamp says")

// The basement case: tapped in, never delivered.
do {
    let s = PendingWork.summarise([row(start: 100, isOpen: true)], lastAttemptAt: nil)
    check(s.waiting == 1 && s.blocked == 0, "an undelivered open shift (its OPEN never landed) is waiting: \(s)")
    check(s.oldestStart == at(100), "oldestStart is the shift's own start")
    check(s.lastAttemptAt == nil, "never attempted reads as nil, NOT as 'just now'")
    check(!s.isEmpty && s.total == 1, "...and it is not empty")
}

// THE OPPOSITE, and it must not be over-reported (Android: "would train the worker to ignore the one banner that matters").
check(PendingWork.summarise([row(open: 10, isOpen: true)], lastAttemptAt: nil).isEmpty,
      "an open shift whose OPEN landed is NOT pending: the server has it and it waits for a tap that has not happened yet")
check(PendingWork.summarise([row(open: 10, close: 20)], lastAttemptAt: nil).isEmpty, "a fully delivered shift is not pending")
check(PendingWork.summarise([row(open: 10)], lastAttemptAt: nil).waiting == 1,
      "half delivered - the OPEN landed, the CLOSE did not - waits: the server holds an open shift the 8h timer will close with a GUESSED end")

// SHIFT EVIDENCE (docs/shift-evidence.md), the two shapes the merge brought in.
// (a) A queued close the server refused with 422 proof_required: Sync.record puts the row back OPEN
//     (endTime nil, syncBlocked false, pendingEvidenceEnd nil) with the open's acknowledgement intact.
check(PendingWork.summarise([row(open: 10, isOpen: true, blocked: false, owed: false)], lastAttemptAt: nil).isEmpty,
      "a row REOPENED by a 422 proof_required is open again, not blocked and not pending")
// (b) A finish that carries a proof: still open locally, but the close is owed and syncPending pushes it.
do {
    let s = PendingWork.summarise([row(open: 10, isOpen: true, owed: true)], lastAttemptAt: nil)
    check(s.waiting == 1 && s.blocked == 0, "a finish owed WITH A PROOF is waiting although the row is still open: \(s)")
    let b = PendingWork.summarise([row(open: 10, isOpen: true, blocked: true, owed: true)], lastAttemptAt: nil)
    check(b.blocked == 1 && b.waiting == 0, "...and blocked when its close was refused terminally: \(b)")
}

// Blocked is counted SEPARATELY and never folded into waiting ("wait for a signal" vs "phone the office").
do {
    let s = PendingWork.summarise([row(start: 5, blocked: true)], lastAttemptAt: nil)
    check(s.blocked == 1 && s.waiting == 0, "a blocked row is blocked, not waiting: \(s)")
    check(s.total == 1, "...but it still counts as something this phone is holding")
    let both = PendingWork.summarise([row(start: 5, blocked: true), row(start: 9)], lastAttemptAt: nil)
    check(both.blocked == 1 && both.waiting == 1 && both.total == 2, "blocked and waiting side by side stay two numbers: \(both)")
    let only = PendingWork.summarise([row(blocked: true), row(blocked: true)], lastAttemptAt: nil)
    check(only.waiting == 0 && only.blocked == 2, "a queue of blocked rows reports waiting == 0: \(only)")
}

// Oldest across a mixed queue: the earliest UNSENT start, waiting or blocked - and not the earliest row.
do {
    let s = PendingWork.summarise([row(start: 900),
                                   row(start: 100, blocked: true),
                                   row(start: 50, open: 60, close: 70)], lastAttemptAt: nil)
    check(s.waiting == 1 && s.blocked == 1, "the delivered row is counted by nobody: \(s)")
    check(s.oldestStart == at(100), "oldest UNSENT start spans waiting AND blocked, not the oldest row: \(String(describing: s.oldestStart))")
}

// THE INVARIANT THAT KEEPS THE TWO HALVES HONEST: every row the engine would try or has refused is
// counted; the row it ignores is counted by nobody (Android core-check "every row SyncPlan would send OR block").
do {
    let queue = [
        row(start: 100),                                            // open to send
        row(start: 200, open: 10),                                  // close to send
        row(start: 300, blocked: true),                             // refused / another account's
        row(start: 400, open: 10, isOpen: true),                    // nothing to do
        row(start: 500, open: 10, isOpen: true, owed: true),        // a proof-close to send
        row(start: 600, open: 10, close: 20),                       // delivered
    ]
    let s = PendingWork.summarise(queue, lastAttemptAt: nil)
    check(s.total == 4, "total == the four rows the engine touches (send, send, refused, proof-close): \(s)")
    check(PendingWork.summarise([queue[3], queue[5]], lastAttemptAt: nil).isEmpty, "...and the two it ignores are counted by nobody")
}

// 1b. THE GRACE. iOS writes the row BEFORE the POST, so every online clock-in and clock-out is "not delivered" for
//     one request. Without a grace the idle list would pop "1 shift still on this phone" in and out after every
//     normal tap (and on the running screen it would say so beside a heading that, by P5's grace, does not).
do {
    let justTapped = row(start: 1_000)                                    // opened on the phone, nothing answered
    func held(_ r: PendingRow, at seconds: Double) -> Bool { PendingWork.isInFlight(r, now: at(seconds)) }
    check(PendingWork.settleGrace == 2, "the grace is 2 seconds")
    check(held(justTapped, at: 1_000) && held(justTapped, at: 1_001.9),
          "a start whose request has been out for under 2 s is IN FLIGHT: no row for it yet")
    check(!held(justTapped, at: 1_002) && !held(justTapped, at: 5_000),
          "...and at 2 s, or an old unacknowledged start (the app was reopened), it is a waiting row at once")
    let closed = PendingRow(startTime: at(100), openSyncedAt: at(100), closeSyncedAt: nil, isOpen: false, syncBlocked: false,
                            lastChangedAt: at(7_200))
    check(held(closed, at: 7_201) && !held(closed, at: 7_203),
          "a FINISH is held back by the finish time, not by the shift's start (the start is hours old)")
    check(PendingRow(startTime: at(5), openSyncedAt: nil, closeSyncedAt: nil, isOpen: true, syncBlocked: false).lastChangedAt == at(5),
          "lastChangedAt falls back to the start when nothing was changed since")
    let refused = row(start: 1_000, blocked: true)
    check(!held(refused, at: 1_000.5), "a BLOCKED row is never held back: the server has answered and the answer was no")
    check(!held(row(start: 1_000, open: 1_000, isOpen: true), at: 1_000.5), "a delivered row is not 'in flight' either (it is not counted at all)")
    check(!held(justTapped, at: 990), "a phone whose clock jumped BACKWARDS does not hide a row (a negative age is not 'young')")
    let proofClose = PendingRow(startTime: at(0), openSyncedAt: at(0), closeSyncedAt: nil, isOpen: true, syncBlocked: false,
                                finishOwed: true, lastChangedAt: at(300))
    check(held(proofClose, at: 301) && !held(proofClose, at: 303), "a proof-close in flight is held back by its own send time")

    let mixed = [justTapped, row(start: 10), refused]
    check(PendingWork.settled(mixed, now: at(1_001)).count == 2 && PendingWork.settled(mixed, now: at(1_001)).contains(refused),
          "settled() drops only the in-flight row, keeps the old waiting row and the refused one")
    check(PendingWork.summarise(PendingWork.settled([justTapped], now: at(1_001)), lastAttemptAt: nil).isEmpty
          && PendingWork.summarise(PendingWork.settled([justTapped], now: at(1_003)), lastAttemptAt: nil).waiting == 1,
          "the count for a normal online tap is nothing at 1 s and one waiting row at 3 s - the failure case reads as a failure")
    check(PendingWork.nextSettle([justTapped], now: at(1_000.5)) == at(1_002), "nextSettle names the moment the earliest held row settles")
    check(PendingWork.nextSettle([justTapped, closed], now: at(7_200.5)) == at(7_202),
          "nextSettle looks only at rows still held back (the old unacknowledged start is not one of them)")
    check(PendingWork.nextSettle([row(start: 10), refused], now: at(1_000)) == nil, "nothing held back, nothing to wake for")
    check(PendingWork.nextSettle([justTapped], now: at(1_005)) == nil, "...and once it has settled there is nothing left to wake for")
}

// THE STRUCTURAL GUARANTEE: state(of:) IS the old inline filter of syncPending, over every combination.
//   `!shift.syncBlocked && (!shift.isFullySynced || shift.pendingEvidenceEnd != nil)`
// (quoted from Sync.swift as it was before this change; Shift.isFullySynced is
//  `openSyncedAt != nil && (isOpen || closeSyncedAt != nil)`).
do {
    var combos = 0, disagreements: [String] = []
    for open in [nil, 10.0] as [Double?] {
        for close in [nil, 20.0] as [Double?] {
            for isOpen in [true, false] {
                for blocked in [true, false] {
                    for owed in [true, false] {
                        let r = row(open: open, close: close, isOpen: isOpen, blocked: blocked, owed: owed)
                        let fullySynced = open != nil && (isOpen || close != nil)
                        let engineTries = !blocked && (!fullySynced || owed)
                        let engineOrRefusal = !fullySynced || owed          // what the screen must account for
                        let s = PendingWork.state(of: r)
                        combos += 1
                        if (s == .waiting) != engineTries { disagreements.append("waiting \(r)") }
                        if (s != .delivered) != engineOrRefusal { disagreements.append("delivered \(r)") }
                        if (s == .blocked) != (blocked && engineOrRefusal) { disagreements.append("blocked \(r)") }
                        if PendingWork.isFullySynced(r) != fullySynced { disagreements.append("isFullySynced \(r)") }
                    }
                }
            }
        }
    }
    check(combos == 32, "all 32 combinations of the five inputs were walked (\(combos))")
    check(disagreements.isEmpty, "state(of:) agrees with the engine's own filter in every combination (\(disagreements.prefix(3)))")
}

// ---------------------------------------------------------------------------------
// 2. The last attempt
// ---------------------------------------------------------------------------------

do {
    let waiting = row(start: 1_000)
    check(PendingWork.summarise([waiting], lastAttemptAt: at(1_100)).lastAttemptAt == at(1_100),
          "an attempt after the earliest unsent start is reported as it is")
    check(PendingWork.summarise([waiting], lastAttemptAt: at(1_000)).lastAttemptAt == at(1_000),
          "an attempt at the very moment of the start is reported (the tap writes the row and pushes straight after)")
    check(PendingWork.summarise([waiting], lastAttemptAt: at(900)).lastAttemptAt == nil,
          "an attempt BEFORE the earliest unsent start is not shown: it cannot have been about this row, and 'Last attempt: yesterday' under a never-tried shift is a lie")
    check(PendingWork.summarise([waiting], lastAttemptAt: nil).lastAttemptAt == nil, "no attempt reads as nil, never as a made-up time")
    // spans a mixed queue: judged against the EARLIEST unsent start, waiting or blocked.
    check(PendingWork.summarise([row(start: 2_000), row(start: 1_000, blocked: true)], lastAttemptAt: at(1_500)).lastAttemptAt == at(1_500),
          "the guard uses the earliest unsent start across waiting and blocked rows")
}

// DeliveryAttempt, against a throwaway defaults suite.
do {
    let suite = "pending-work-check-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    check(DeliveryAttempt.last(in: defaults) == nil, "a phone that never tried reads nil")
    DeliveryAttempt.stamp(at: at(100), in: defaults)
    check(DeliveryAttempt.last(in: defaults) == at(100), "stamp writes the attempt time")
    DeliveryAttempt.stamp(at: at(250), in: defaults)
    check(DeliveryAttempt.last(in: defaults) == at(250), "a later attempt replaces it (one global value)")
    check(DeliveryAttempt.date(seconds: 0) == nil && DeliveryAttempt.date(seconds: -5) == nil,
          "0 (the @AppStorage default) and a negative value both mean 'never'")
    check(DeliveryAttempt.date(seconds: 1_700_000_000) == t0, "the stored value is seconds since 1970")
    check(!DeliveryAttempt.defaultsKey.isEmpty && !DeliveryAttempt.defaultsKey.contains("flag."),
          "the key is its own, not a feature flag's")
}

// ---------------------------------------------------------------------------------
// 3. The words
// ---------------------------------------------------------------------------------

do {
    let own = PendingWork.summarise([row(start: 1)], lastAttemptAt: nil)
    let foreignOnly = PendingWork.summarise([row(start: 1, open: 1, other: true)], lastAttemptAt: nil)
    let mixed = PendingWork.summarise([row(start: 1), row(start: 2, open: 1, other: true)], lastAttemptAt: nil)
    let blockedOnly = PendingWork.summarise([row(start: 1, blocked: true)], lastAttemptAt: nil)

    check(PendingWork.waitingSentence(for: own, signedOut: false) == .notActive,
          "signed in, own rows: the 'automatic delivery is not active, open the app' sentence - true at every moment on iOS")
    check(PendingWork.waitingSentence(for: own, signedOut: true) == .signIn,
          "SIGNED OUT: 'sign in with the same account' - never 'open the app', which cannot send anything")
    check(PendingWork.waitingSentence(for: foreignOnly, signedOut: false) == .signIn,
          "every waiting row belongs to another account: opening the app cannot send them, signing in as theirs can")
    check(foreignOnly.waitingForOthers == 1 && own.waitingForOthers == 0 && mixed.waitingForOthers == 1,
          "waitingForOthers counts only waiting rows queued by another account")
    check(PendingWork.waitingSentence(for: mixed, signedOut: false) == .notActive,
          "in a mix the signed-in worker's own rows win: the sentence must be true for the rows they can act on")
    check(PendingWork.waitingSentence(for: blockedOnly, signedOut: false) == nil
          && PendingWork.waitingSentence(for: blockedOnly, signedOut: true) == nil
          && PendingWork.waitingSentence(for: PendingWork.nothing, signedOut: true) == nil,
          "no waiting rows, no waiting sentence: nothing under a count that is not on screen")
    check(PendingWork.summarise([row(start: 1, blocked: true, other: true)], lastAttemptAt: nil).waitingForOthers == 0,
          "a BLOCKED row of another account is blocked, not 'waiting for others'")
}

// ---------------------------------------------------------------------------------
// 4. The wiring, read as text
// ---------------------------------------------------------------------------------

func source(_ name: String) -> String {
    guard let text = try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: cannot read NFCTimeSheets/\(name)\n".utf8)); exit(1)
    }
    return text
}
/// Code only: comments and doc comments carry the rationale and quote the very things this check bans.
func code(_ s: String) -> String {
    s.components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}
func between(_ s: String, _ from: String, _ to: String) -> String {
    let parts = s.components(separatedBy: from)
    guard parts.count > 1 else { return "" }
    return parts[1].components(separatedBy: to)[0]
}
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}
func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

let workText = code(source("PendingWork.swift"))
let viewsText = code(source("DeliveryStatusViews.swift"))
let sync = code(source("Sync.swift"))
let view = code(source("ContentView.swift"))
let screen = code(source("ShiftScreen.swift"))
let scope = code(source("WorkerScope.swift"))
let app = code(source("NFCTimeSheetsApp.swift"))

// --- the engine and the screens count with ONE predicate -------------------------
let pass = between(sync, "func syncPending(", "\n}")
check(pass.contains("for shift in all where PendingWork.state(of: shift.deliveryRow()) == .waiting {"),
      "syncPending iterates exactly the rows PendingWork calls WAITING - one predicate, spelled once")
check(!pass.contains("shift.isFullySynced") && !pass.contains("!shift.syncBlocked"),
      "...and the old inline filter is gone from syncPending: no second definition to drift")
let mapping = between(sync, "func deliveryRow(sessionWorkerId: Int? = nil) -> PendingRow {", "\n    }")
check(mapping.contains("startTime: startTime,") && mapping.contains("openSyncedAt: openSyncedAt,")
      && mapping.contains("closeSyncedAt: closeSyncedAt,") && mapping.contains("isOpen: isOpen,")
      && mapping.contains("syncBlocked: syncBlocked,") && mapping.contains("finishOwed: pendingEvidenceEnd != nil,")
      && mapping.contains("queuedByAnotherAccount: sessionWorkerId.map { $0 != workerId } ?? false,")
      && mapping.contains("lastChangedAt: pendingEvidenceEnd ?? endTime ?? startTime)"),
      "Shift.deliveryRow maps the five facts one-to-one, the owed proof from pendingEvidenceEnd, 'another account' from the session and the last local write")
check(inOrder(code(source("PendingNotice.swift")), ["static let grace: TimeInterval = 2"]) && workText.contains("static let settleGrace: TimeInterval = 2"),
      "the delivery grace IS PendingNotice.grace (2 s): the 'Not confirmed yet' heading and the waiting row appear at the same moment")
check(app.contains("var isFullySynced: Bool { openSyncedAt != nil && (isOpen || closeSyncedAt != nil) }")
      && workText.contains("row.openSyncedAt != nil && (row.isOpen || row.closeSyncedAt != nil)"),
      "PendingWork.isFullySynced is Shift.isFullySynced spelled on the value (the model line is unchanged)")
check(workText.contains("if isFullySynced(row) && !row.finishOwed { return .delivered }")
      && workText.contains("return row.syncBlocked ? .blocked : .waiting"),
      "state(of:): delivered, else blocked, else waiting")

// --- the stamp: after the guards, before the request, and only where a request leaves the phone ----
let openBody = between(sync, "private func pushOpen(", "\n}")
let closeBody = between(sync, "private func pushClose(", "\n}")
check(inOrder(openBody, ["guard TagLink.normalizedUUID(shift.locationId) != nil else {", "guard shift.workerId == workerId else {",
                         "DeliveryAttempt.stamp()", "try await ShiftFlowAPI.open("]),
      "pushOpen stamps AFTER both local guards (a row it refuses sends nothing) and BEFORE the request")
check(inOrder(closeBody, ["guard shift.workerId == workerId else { return }", "DeliveryAttempt.stamp()", "try await ShiftFlowAPI.close("]),
      "pushClose stamps after the skip-another-account guard and before the request")
check(count(sync, "DeliveryAttempt.stamp()") == 2, "the sync engine stamps in exactly two places: the open and the close")
let proofClose = between(view, ".sheet(item: $proofShift", "// Coming back from the background")
check(inOrder(proofClose, ["DeliveryAttempt.stamp()", "try await ShiftAPI.close("]),
      "the proof-close is a delivery attempt too, stamped before its request")
check(count(view, "DeliveryAttempt.stamp()") == 1, "ContentView stamps in exactly one place: the proof-close")
check(!between(sync, "private func record(", "\n}").contains("DeliveryAttempt") && !between(sync, "private func apply(", "\n}").contains("DeliveryAttempt"),
      "a failure or an acknowledgement does not stamp: the stamp is 'a push was tried', not 'a push ended'")

// --- DISPLAY ONLY: nothing on the tap path, in the sync pass, the signals or navigation reads it -------
for (name, from, to) in [
    ("refresh()", "private func refresh() async {", "\n    }"),
    ("handleTap", "private func handleTap(", "\n    private func outcome("),
    ("startManual", "private func startManual() {", "private func manualStop() {"),
    ("manualStop", "private func manualStop() {", "\n    }"),
    ("finishManualStop", "private func finishManualStop() {", "\n    #if DEBUG"),
    ("prepareCompletion", "private func prepareCompletion(", "\n    }"),
    ("scan", "private func scan() {", "\n    }"),
    ("currentRunning", "private func currentRunning() -> RunningShift? {", "\n    }"),
    ("armIfStillCurrent", "private func armIfStillCurrent() {", "\n    }"),
    ("asRunning", "private func asRunning(_ shift: Shift) -> RunningShift {", "\n    }"),
] {
    let body = between(view, from, to)
    check(!body.isEmpty, "found \(name) in ContentView.swift")
    check(!body.contains("deliveryRows") && !body.contains("DeliveryStatus") && !body.contains("PendingWork")
          && !body.contains("PendingRow") && !body.contains("deviceWide") && !body.contains("DeliveryAttempt")
          && !body.contains("phoneRows") && !body.contains("deliveryTick") && !body.contains("deliverySettleAt"),
          "\(name) never reads the delivery summary (display only: it can never gate, delay or alter a tap, a sync or a signal)")
}
check(!between(view, "private func asRunning(", "\n    }").contains("deliveryRow"),
      "the running value (what every signal is armed from) is built without the summary")
for name in ["ShiftSignal.swift", "ShiftSignalCenter.swift", "TapInbox.swift", "TapScanner.swift", "Auth.swift", "ManualStart.swift",
             "Zones.swift", "RosterZones.swift", "AppUpdate.swift", "Telemetry.swift", "MaterialStore.swift", "MaterialsView.swift",
             "ScheduleStore.swift", "PendingNotice.swift", "PendingNoticeView.swift", "ShiftActivityAttributes.swift",
             "LiveActivityController.swift", "OperatorSession.swift", "OperatorAPI.swift"] {
    let text = code(source(name))
    check(!text.contains("PendingWork") && !text.contains("DeliveryStatus") && !text.contains("DeliveryAttempt")
          && !text.contains("PendingRow") && !text.contains("deliveryRow"),
          "\(name) does not know the delivery summary exists (it is never an input to a tap, a signal, a session or a cache)")
}
check(count(code(source("Sync.swift")), "PendingRow") == 2 && count(sync, "PendingWork.") == 1,
      "Sync.swift's only contact with the summary is the one predicate and the row mapping")

// --- device-wide ONLY through WorkerScope, and only as the summary's input ------------
check(scope.contains("func deviceWide() -> [Element] {") && scope.contains("Array(self)"),
      "WorkerScope owns the one unscoped read, named for what it is")
check(count(view, ".deviceWide()") == 2, "ContentView makes exactly two device-wide reads: LogView's and SignInView's delivery rows")
check(view.contains("allShifts.deviceWide().map { $0.deliveryRow(sessionWorkerId: worker.id) }")
      && view.contains("private var deliveryRows: [PendingRow] { allShifts.deviceWide().map { $0.deliveryRow() } }"),
      "...each only ever mapped to a PendingRow value (LogView with the session worker, the sign-in screen with nobody)")
let signIn = between(view, "struct SignInView: View {", "struct LogView: View {")
check(signIn.contains("@Query private var allShifts: [Shift]"),
      "the sign-in screen reads the store through a Shift @Query with the loud, device-wide name")
check(!signIn.contains("forWorker") && !signIn.contains("openShift(for:") && !signIn.contains("completed(for:"),
      "...and shows no LIST: there is no worker whose rows could be scoped")

// --- the grace is LogView's: the views stay pure, the timer is one display-only task -----------------
check(view.contains("return PendingWork.settled(phoneRows, now: .now)")
      && view.contains("private var deliverySettleAt: Date? { PendingWork.nextSettle(phoneRows, now: .now) }")
      && view.contains("@State private var deliveryTick = 0"),
      "LogView hands the screens SETTLED rows (a tap's unanswered request is held back for the grace) and wakes itself when it settles")
let settleTask = between(view, ".task(id: deliverySettleAt) {", "\n            }")
check(inOrder(settleTask, ["guard let settleAt = deliverySettleAt else { return }", "Task.sleep(for: .seconds(wait))",
                           "if !Task.isCancelled { deliveryTick += 1 }"])
      && !settleTask.contains("syncPending") && !settleTask.contains("context") && !settleTask.contains("handleTap")
      && !settleTask.contains("signals"),
      "the wake-up task only sleeps and bumps a counter: it pushes, saves, arms and taps nothing")
check(count(view, ".task(id: deliverySettleAt)") == 1, "one wake-up task")
check(!code(source("DeliveryStatusViews.swift")).contains("settled(") && !code(source("DeliveryStatusViews.swift")).contains("Date.now"),
      "the views are pure of the clock: they draw the rows they are given")

// --- placement -----------------------------------------------------------------
let idle = between(view, "private var idleList: some View {", "#if DEBUG\n            manualMockSection")
check(inOrder(idle, ["if !unresolved.isEmpty {", "DeliveryStatusRows(rows: deliveryRows, signedOut: false)",
                     "ScheduleSummary(state: schedule.state, retry: loadSchedule)", "Section(\"Recent\")"]),
      "idle: the delivery rows sit right after the unresolved banner and above the plan and Recent")
check(count(idle, "DeliveryStatusRows(") == 1 && !idle.contains("Section {\n                DeliveryStatusRows"),
      "idle: ONE delivery block, NOT wrapped in a Section (an empty Section would still draw a gap)")
let stack = between(screen, "VStack(spacing: 24) {", ".frame(maxWidth: .infinity)")
check(inOrder(stack, ["if unresolvedCount > 0 { resolverCard }", "DeliveryStatusRows(rows: deliveryRows, signedOut: false)",
                      "if signals.outOfAppSignalsSilenced { notificationsOffCard }"]),
      "running: the delivery rows sit after the resolver card (and before notifications-off, the plan and help)")
check(inOrder(stack, ["PendingNoticeView(content: content, onRefresh: onRefresh)", "stopButton", "DeliveryStatusRows("]),
      "running: after the clock, the notice and BOTH controls - the rows never sit between a worker and the way out")
check(stack.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("if ") }.count == 4,
      "running: the stack still has exactly the four conditionals it had (the rows are not conditional HERE)")
check(count(screen, "deliveryRows") == 2 && screen.contains("let deliveryRows: [PendingRow]"),
      "ShiftScreen mentions the rows in exactly two places: its input and the one view")
check(inOrder(signIn, ["Image(\"BrandMark\")", ".listRowBackground(Color.clear)", "DeliveryStatusRows(rows: deliveryRows, signedOut: true)",
                       "CodeSignInSection(role: .worker,"]),
      "sign-in: the rows sit between the brand block and the code form, with signedOut: true")
check(count(view, "signedOut: true") == 1 && count(view, "signedOut: false") == 1 && count(screen, "signedOut: false") == 1,
      "only the sign-in screen says signedOut: true")
check(view.contains("                                deliveryRows: deliveryRows,\n                                syncError: openRow?.syncError,"),
      "LogView hands ShiftScreen the rows (device-wide, mapped) just before the open row's own sync fields")

// --- the views: nothing hidden, no surface, no store ----------------------------
check(viewsText.contains("if !summary.isEmpty {") && inOrder(viewsText, ["struct DeliveryStatusRows: View {", "if !summary.isEmpty {",
                                                                          "DeliveryStatusContent(summary: summary, signedOut: signedOut)"]),
      "DeliveryStatusRows draws NOTHING when the phone holds nothing")
let rowsView = between(viewsText, "struct DeliveryStatusRows: View {", "private struct DeliveryStatusContent: View {")
check(!rowsView.contains("@State") && between(viewsText, "private struct DeliveryStatusContent: View {", "struct DeliveryDetailsSheet: View {").contains("@State private var showDetails = false"),
      "the sheet's state lives in the content that disappears with the last row: a later unsent row can never reopen a stale sheet")
let content = between(viewsText, "private struct DeliveryStatusContent: View {", "struct DeliveryDetailsSheet: View {")
check(inOrder(content, ["if summary.blocked > 0 {", "blockedLabel", "if summary.waiting > 0 {", "waitingLabel"]),
      "the BLOCKED row comes first: it is the one that needs a human")
check(content.contains("Text(\"\\(summary.blocked) shifts need your office\")") && content.contains("Text(\"\\(summary.waiting) shifts still on this phone\")"),
      "the two row labels are the two plural keys, with the Int interpolated (the catalogue picks one/other)")
check(count(content, ".frame(minHeight: 44)") == 2 && count(content, "Button {") == 2 && count(content, ".buttonStyle(.bordered)") == 2,
      "two buttons, both explicitly styled (a default Button swallows a whole List row) and at least 44 pt tall")
check(count(content, ".buttonBorderShape(.roundedRectangle)") == 2,
      "both rows use the system rounded rectangle, not a capsule (a capsule turns into an ellipse around a wrapped count at 200% text)")
check(content.contains(".tint(.red)") && inOrder(content, ["if summary.blocked > 0 {", ".tint(.red)", "if summary.waiting > 0 {"]),
      "only the BLOCKED row is red")
check(content.contains(".sheet(isPresented: $showDetails) {") && content.contains("DeliveryDetailsSheet(summary: summary, signedOut: signedOut)"),
      "both rows open the same details sheet")
check(content.contains("accessibilityHidden(true)"), "the glyphs are decoration: the words beside them say it")

let sheet = between(viewsText, "struct DeliveryDetailsSheet: View {", "\n}\n")
check(!sheet.isEmpty, "found DeliveryDetailsSheet")
check(inOrder(sheet, ["Text(\"Delivery\")", "if summary.blocked > 0 {", ".foregroundStyle(.red)", "if summary.waiting > 0 {",
                      "PendingWork.waitingSentence(for: summary, signedOut: signedOut)", "Divider()", "Earliest shift start:",
                      "Last attempt:", "No delivery attempt yet.", "Text(\"Close\")"]),
      "sheet order: title, blocked count + what to do (red), waiting count + ONE sentence, divider, earliest start, last attempt or none, Close")
check(count(sheet, "case .signIn:") == 1 && count(sheet, "case .notActive:") == 1 && count(sheet, "case nil:") == 1,
      "the waiting sentence is a switch over PendingWork's decision: exactly one arm is drawn")
check(sheet.contains(".presentationDetents([.medium, .large])") && sheet.contains("ScrollView {"),
      "the sheet has .medium/.large detents and scrolls (200% Dynamic Type)")
let scrollEnd = sheet.range(of: "Button { dismiss() } label: {")
let scrollStart = sheet.range(of: "ScrollView {")
check(scrollStart != nil && scrollEnd != nil && scrollStart!.upperBound < scrollEnd!.lowerBound
      && !between(sheet, "ScrollView {", "Button { dismiss() } label: {").isEmpty
      && between(sheet, "ScrollView {", "Button { dismiss() } label: {").contains(".padding(24)\n            }\n"),
      "Close sits OUTSIDE the scroll view, so it is on screen at every text size and detent")
check(count(sheet, "Button {") == 1 && sheet.contains("Button { dismiss() } label: {"),
      "the sheet's one control is Close, and it only dismisses: closing deletes nothing")
check(sheet.contains("summary.oldestStart") && sheet.contains("summary.lastAttemptAt"),
      "the earliest start and the last attempt come from the summary")

for banned in [".background(", ".listRow", "RoundedRectangle", "Capsule(", ".clipShape", ".cornerRadius", ".shadow(", "Color(", "Color.",
               ".overlay(", ".border(", "UIColor", ".foregroundColor(", ".fill(", ".stroke(", ".opacity("] {
    check(!viewsText.contains(banned),
          "DeliveryStatusViews.swift has no hard-coded surface (found '\(banned)'): the Blue Hour reskin restyles the container, not these views")
}
let styles = viewsText.components(separatedBy: ".foregroundStyle(").dropFirst().map { $0.components(separatedBy: ")")[0] }
check(styles == [".red"], "the only colour in the sheet is the red of the blocked count (got \(styles))")
check(count(viewsText, ".tint(") == 1, "the only tint is the blocked row's red")
for banned in ["@Environment(\\.modelContext", "@Environment(Session", "@Query", "ModelContext", "SwiftData", "ShiftAPI", "ShiftFlowAPI", "URLSession",
               "apiGet", "apiPost", "handleTap", "TapInbox", "ShiftSignal", "OperatorAPI", ".disabled(", ".hidden()", "context.delete", "UIApplication"] {
    check(!viewsText.contains(banned), "DeliveryStatusViews.swift is display only: it cannot reach '\(banned)'")
}
check(!workText.contains("import SwiftUI") && !workText.contains("import UIKit") && !workText.contains("import SwiftData")
      && !workText.contains("ModelContext") && !workText.contains("@Model") && !workText.contains("URLSession"),
      "PendingWork.swift is Foundation-only")
check(count(workText, "UserDefaults") >= 1 && !between(workText, "enum PendingWork {", "enum DeliveryAttempt {").contains("UserDefaults"),
      "UserDefaults appears only in DeliveryAttempt: the count itself persists nothing")
check(!viewsText.contains("? Text(") && !viewsText.contains("Text(blocked ?") && !viewsText.contains("Text(verbatim: \""),
      "no ternary of two string literals (the verbatim initialiser ships English, TASK-298) and no verbatim literal sentence")
check(viewsText.contains("@AppStorage(DeliveryAttempt.defaultsKey) private var lastAttemptSeconds: Double = 0"),
      "the last attempt reaches the screen through @AppStorage, so a push that stamps it redraws an open sheet")

// ---------------------------------------------------------------------------------
// 5. The strings: both languages, the exact keys, the German is Android's
// ---------------------------------------------------------------------------------

guard let catalogueData = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
      let catalogueRoot = try? JSONSerialization.jsonObject(with: catalogueData) as? [String: Any],
      let catalogue = catalogueRoot["strings"] as? [String: Any]
else { print("FAIL: Localizable.xcstrings unreadable"); exit(1) }

func localized(_ key: String, _ lang: String) -> [String: Any]? {
    ((catalogue[key] as? [String: Any])?["localizations"] as? [String: Any])?[lang] as? [String: Any]
}
func german(_ key: String) -> String? { (localized(key, "de")?["stringUnit"] as? [String: Any])?["value"] as? String }
func plural(_ key: String, _ lang: String, _ category: String) -> String? {
    (((localized(key, lang)?["variations"] as? [String: Any])?["plural"] as? [String: Any])?[category] as? [String: Any])
        .flatMap { $0["stringUnit"] as? [String: Any] }.flatMap { $0["value"] as? String }
}
func androidStrings(_ path: String) -> (strings: [String: String], plurals: [String: [String: String]]) {
    guard let xml = try? String(contentsOfFile: path, encoding: .utf8) else {
        check(false, "cannot read \(path) - the German of this feature is read out of it"); return ([:], [:])
    }
    func clean(_ s: String) -> String { s.replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "&amp;", with: "&") }
    var out: [String: String] = [:]
    let entry = try! NSRegularExpression(pattern: #"<string name="([^"]+)"[^>]*>([\s\S]*?)</string>"#)
    for m in entry.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
        out[String(xml[Range(m.range(at: 1), in: xml)!])] = clean(String(xml[Range(m.range(at: 2), in: xml)!]))
    }
    var plurals: [String: [String: String]] = [:]
    let block = try! NSRegularExpression(pattern: #"<plurals name="([^"]+)">([\s\S]*?)</plurals>"#)
    let item = try! NSRegularExpression(pattern: #"<item quantity="([^"]+)">([\s\S]*?)</item>"#)
    for m in block.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
        let body = String(xml[Range(m.range(at: 2), in: xml)!])
        var items: [String: String] = [:]
        for im in item.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            items[String(body[Range(im.range(at: 1), in: body)!])] = clean(String(body[Range(im.range(at: 2), in: body)!]))
        }
        plurals[String(xml[Range(m.range(at: 1), in: xml)!])] = items
    }
    return (out, plurals)
}
let res = "../android/app/src/main/res"
let androidDe = androidStrings("\(res)/values/strings.xml")          // default resources ARE German
let androidEn = androidStrings("\(res)/values-en/strings.xml")
/// The key the compiler extracts: non-positional, %d -> %lld, %s -> %@.
func iosKey(_ s: String) -> String {
    s.replacingOccurrences(of: #"%\d+\$d"#, with: "%lld", options: .regularExpression)
        .replacingOccurrences(of: #"%\d+\$s"#, with: "%@", options: .regularExpression)
        .replacingOccurrences(of: "%d", with: "%lld").replacingOccurrences(of: "%s", with: "%@")
}

// (Android name, the iOS key, the literal as the view writes it) - German is Android's, verbatim.
let verbatim: [(String, String, String)] = [
    ("delivery_title", "Delivery", "Text(\"Delivery\")"),
    ("delivery_sign_in", "Sign in with the same account so these entries can be delivered.",
     "Text(\"Sign in with the same account so these entries can be delivered.\")"),
    ("delivery_not_scheduled", "Automatic delivery is not currently active. Open the app with an internet connection to try delivery again.",
     "Text(\"Automatic delivery is not currently active. Open the app with an internet connection to try delivery again.\")"),
    ("pending_oldest", "Earliest shift start: %@", "Text(\"Earliest shift start: \\(AppLanguage.formatted(oldest, date: .abbreviated, time: .shortened, locale: locale))\")"),
    ("pending_last_try", "Last attempt: %@", "Text(\"Last attempt: \\(AppLanguage.formatted(attempt, date: .abbreviated, time: .shortened, locale: locale))\")"),
    ("delivery_no_attempt", "No delivery attempt yet.", "Text(\"No delivery attempt yet.\")"),
]
for (name, key, written) in verbatim {
    guard let de = androidDe.strings[name], let en = androidEn.strings[name] else { check(false, "Android has string '\(name)'"); continue }
    check(iosKey(en) == key, "the iOS key for Android's \(name) is Android's English: '\(iosKey(en))' vs '\(key)'")
    check(german(key) == iosKey(de), "the German for '\(key)' is Android's \(name), verbatim: '\(german(key) ?? "nil")' vs '\(iosKey(de))'")
    check(viewsText.contains(written), "DeliveryStatusViews.swift shows '\(key)' through the catalogue, written exactly '\(written)'")
}
check(german("Close") == "Schließen" && viewsText.contains("Text(\"Close\")"), "'Close' is P4's key, German 'Schließen'")

// THE ONE DELIBERATE EXCEPTION (decision-82 section 4): Android's blocked detail promises nothing, but it
// says "will not retry automatically" / "nicht automatisch erneut gesendet" - the word this surface may not
// contain on a platform with no automatic anything. Same sentence, adverb dropped, asserted to the character.
guard let blockedEnAndroid = androidEn.strings["delivery_blocked_detail"], let blockedDeAndroid = androidDe.strings["delivery_blocked_detail"]
else { fatalError("Android has delivery_blocked_detail") }
let blockedKey = "Your office needs to review these entries. They remain on this phone and are not sent again. Please tell your office the time shown below."
let blockedDe = "Die Verwaltung muss diese Einträge prüfen. Sie bleiben auf diesem Telefon gespeichert und werden nicht erneut gesendet. Bitte nennen Sie der Verwaltung die unten angezeigte Zeit."
check(blockedEnAndroid.replacingOccurrences(of: "will not retry automatically", with: "are not sent again") == blockedKey,
      "the iOS blocked detail is Android's English with only 'will not retry automatically' -> 'are not sent again'")
check(blockedDeAndroid.replacingOccurrences(of: "nicht automatisch erneut gesendet", with: "nicht erneut gesendet") == blockedDe,
      "the German is Android's with only 'nicht automatisch erneut gesendet' -> 'nicht erneut gesendet'")
check(german(blockedKey) == blockedDe, "the catalogue holds that German")
check(viewsText.contains("Text(\"\(blockedKey)\")"), "the sheet shows the blocked detail through the catalogue")
check(blockedKey.contains("Please tell your office the time shown below."),
      "the blocked detail still gives the worker the time to tell the office (the 'Earliest shift start' line below it)")

// The two counts: real one/other, in BOTH languages, German noun AND verb agreeing, and Android's own words.
for (name, key, deOne, deOther, enOne) in [
    ("delivery_blocked_short", "%lld shifts need your office", "%lld Schicht braucht die Verwaltung",
     "%lld Schichten brauchen die Verwaltung", "%lld shift needs your office"),
    ("delivery_waiting_short", "%lld shifts still on this phone", "%lld Schicht noch auf diesem Telefon",
     "%lld Schichten noch auf diesem Telefon", "%lld shift still on this phone"),
] {
    guard let aDe = androidDe.plurals[name], let aEn = androidEn.plurals[name] else { check(false, "Android has plurals '\(name)'"); continue }
    check(iosKey(aEn["other"] ?? "") == key, "the iOS key for Android's \(name) is its English 'other' form")
    check(plural(key, "de", "one") == iosKey(aDe["one"] ?? "") && plural(key, "de", "one") == deOne,
          "\(key): German 'one' is Android's, verbatim ('\(plural(key, "de", "one") ?? "nil")')")
    check(plural(key, "de", "other") == iosKey(aDe["other"] ?? "") && plural(key, "de", "other") == deOther,
          "\(key): German 'other' is Android's, verbatim ('\(plural(key, "de", "other") ?? "nil")')")
    check(plural(key, "en", "one") == iosKey(aEn["one"] ?? "") && plural(key, "en", "one") == enOne,
          "\(key): English 'one' is Android's ('\(plural(key, "en", "one") ?? "nil")')")
    check(plural(key, "en", "other") == key, "\(key): English 'other' is the key itself")
    check(content.contains("Text(\"\\(summary.\(key.contains("office") ? "blocked" : "waiting")) \(key.dropFirst(5))\")"),
          "\(key) is drawn with its count interpolated")
}

// WORDING: nothing on this surface promises automatic delivery or mentions force-stopping. Every string
// the views can show, in both languages, plural forms included.
var surface: [String] = verbatim.map { $0.1 } + [blockedKey, blockedDe, "Delivery"]
for (_, key, _) in verbatim { if let v = german(key) { surface.append(v) } }
for key in ["%lld shifts need your office", "%lld shifts still on this phone"] {
    surface.append(key)
    for lang in ["de", "en"] { for cat in ["one", "other"] { if let v = plural(key, lang, cat) { surface.append(v) } } }
}
check(surface.count >= 20, "the wording scan covers the whole surface (\(surface.count) strings)")
let forbidden = try! NSRegularExpression(
    pattern: #"automatically|\bautomatisch\b|force[- ]?stop|zwangs|App stoppen|battery|akku|background|hintergrund|try again on its own|from time to time"#,
    options: [.caseInsensitive])
for text in surface {
    check(forbidden.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil,
          "no delivery string may promise automatic delivery or mention force-stopping (iOS has neither): '\(text)'")
}
// ...and the ONE place the adjective appears is the sentence that says it is NOT active.
let adjective = try! NSRegularExpression(pattern: #"automatic|automatische"#, options: [.caseInsensitive])
for text in surface where adjective.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
    check(text.contains("not currently active") || text.contains("nicht aktiv"),
          "the word 'automatic' appears only to say delivery is NOT active: '\(text)'")
}
let signInSentences = ["Sign in with the same account so these entries can be delivered.", german("Sign in with the same account so these entries can be delivered.") ?? "?"]
check(signInSentences.allSatisfy { !$0.lowercased().contains("open the app") && !$0.contains("Öffnen Sie die App") },
      "the sign-in sentence never says 'open the app' (on the sign-in screen that cannot send anything)")
let notActive = "Automatic delivery is not currently active. Open the app with an internet connection to try delivery again."
check(notActive.contains("Open the app") && (german(notActive) ?? "").contains("Öffnen Sie die App"),
      "the signed-in sentence says what to do: open the app with a connection")

// Every literal the views pass to Text / Button is a catalogue key with a German value.
let literal = try! NSRegularExpression(pattern: #"(?:Text|Button|accessibilityLabel)\("([^"\\]+)""#)
var shown: Set<String> = []
for match in literal.matches(in: viewsText, range: NSRange(viewsText.startIndex..., in: viewsText)) {
    let key = String(viewsText[Range(match.range(at: 1), in: viewsText)!])
    shown.insert(key)
    check(catalogue[key] != nil && (german(key) != nil), "DeliveryStatusViews.swift shows the literal '\(key)', which must be a catalogue key with a German value")
}
check(shown.contains("Delivery") && shown.contains("Close") && shown.count == 6,
      "the views show exactly their six plain literals (Delivery, Close, three sentences, no attempt): \(shown.sorted())")
let interpolated = try! NSRegularExpression(pattern: #"Text\("([^"]*\\\([^"]*)"\)"#)
let interpolatedKeys = interpolated.matches(in: viewsText, range: NSRange(viewsText.startIndex..., in: viewsText)).count
check(interpolatedKeys == 6, "...and exactly six interpolated literals: two counts (twice) and the two time lines (\(interpolatedKeys))")
check(!(try! String(contentsOfFile: "NFCTimeSheets/Localizable.xcstrings", encoding: .utf8)).contains("Gebäude"),
      "buildings are 'Objekt', never 'Gebäude'")

if failed { exit(1) }
print("pending-work-check: OK")
