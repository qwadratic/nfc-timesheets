// Runnable check: a shared phone belongs to whoever is signed in (TASK-365.4, iOS P3).
//
//   cd NFCTimeSheets
//   cat NFCTimeSheets/WorkerScope.swift checks/worker-scope-check.swift \
//     > /tmp/worker-scope-check.swift && swift /tmp/worker-scope-check.swift
//
// WHY: the SwiftData store is the PHONE's outbox, across every account that ever signed in on it,
// and every read of it used to be unscoped. Worker B saw A's History and totals, could swipe-delete
// A's rows, inherited A's running screen, tab lock, reminders and material context, and B's FIRST
// TAP closed A's open row - the close going out under B's cookie, where the server answers 404
// unknown_shift. Android scoped every read in PR 5/7 (ShiftStore.forWorker / openShift(workerId)).
//
// TWO HALVES, because the bug is "ONE MISSED READ SITE LEAVES A CROSS-WORKER TOGGLE":
//   1. the helper's BEHAVIOUR (WorkerScope.swift, run for real, with a struct standing in for Shift);
//   2. the SCREENS, read as text (ContentView.swift, MaterialsView.swift, Auth.swift, Sync.swift):
//      no Shift @Query that is not named allShifts, no use of allShifts that skips the helper, no raw
//      `.isOpen` read, the TabView carries .id(worker.id), sign-out tears the signals down, foreign
//      rows are never deleted, and the tap path was not given a new gate.
//
// P6 (TASK-365.7, decision-82) added the ONE deliberate device-wide read: the delivery summary counts
// what the phone still holds for EVERY account, on the idle list, the running screen and the sign-in
// screen. It has exactly one name, WorkerScope's `deviceWide()`, and this check allows it in
// ContentView.swift only as the input of that summary (see "THE DEVICE-WIDE READ" below) - the rule
// "every use of allShifts goes through the helper" is unchanged, it just has a fourth helper.
//
// RED CASES reproduced before this was trusted (see the commit): an unscoped
// `allShifts.first(where: \.isOpen)` in handleTap; a Shift @Query still named `shifts`; HistoryView
// listing allShifts; the .id(worker.id) removed; clearLocalSession without the arm(nil); a stale
// refresh arming without the current-worker guard; pushClose without the worker guard.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

// ---------------------------------------------------------------------------------
// 1. The helper
// ---------------------------------------------------------------------------------

struct Row: WorkerScoped, Equatable {
    let tag: String
    let workerId: Int
    let startTime: Date
    let endTime: Date?
}
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }
let A = 7, B = 9

let aOpen = Row(tag: "A open", workerId: A, startTime: at(0), endTime: nil)
let aDone = Row(tag: "A done", workerId: A, startTime: at(-30), endTime: at(-22))
let aOpenOlder = Row(tag: "A open older", workerId: A, startTime: at(-60), endTime: nil)
let bDone = Row(tag: "B done", workerId: B, startTime: at(-26), endTime: at(-18))
let bOpen = Row(tag: "B open", workerId: B, startTime: at(2), endTime: nil)
let legacyOpen = Row(tag: "legacy open", workerId: 0, startTime: at(1), endTime: nil)
let legacyDone = Row(tag: "legacy done", workerId: 0, startTime: at(-40), endTime: at(-39))

// THE BUG: A left a shift open and B picked up the phone.
let sharedStore = [aOpen, aDone, bDone, legacyOpen, legacyDone]   // newest first, like the @Query
check(sharedStore.openShift(for: B) == nil,
      "B has NO open shift while only A's row is open - B's tap must start B's own shift, not close A's")
check(sharedStore.openShift(for: A) == aOpen, "A's own open row is still A's")
check(sharedStore.forWorker(B) == [bDone], "B sees only B's rows: no A row, no legacy row (\(sharedStore.forWorker(B).map(\.tag)))")
check(sharedStore.completed(for: B) == [bDone], "B's totals and Recent are made of B's finished rows only")
check(sharedStore.forWorker(A) == [aOpen, aDone], "A sees A's rows, in the order the query gave them")
check(sharedStore.completed(for: A) == [aDone], "A's finished rows exclude A's open one")

// Both open: each toggles their own.
let bothOpen = [bOpen, aOpen, aDone]
check(bothOpen.openShift(for: B) == bOpen && bothOpen.openShift(for: A) == aOpen,
      "with both accounts holding an open row, each tap toggles its own account's row")

// Newest open row, whatever order the sequence arrives in (Android: ORDER BY start_time DESC LIMIT 1).
check([aOpenOlder, aOpen].openShift(for: A) == aOpen && [aOpen, aOpenOlder].openShift(for: A) == aOpen,
      "the newest open row is the one a tap toggles, independent of input order")

// Legacy rows (workerId 0) belong to nobody and are listed for nobody - not even for id 0.
check(!sharedStore.forWorker(A).contains(legacyOpen) && !sharedStore.forWorker(B).contains(legacyDone),
      "a legacy row (workerId 0) is in nobody's list")
check([legacyOpen].openShift(for: 0) == nil && [legacyOpen, legacyDone].forWorker(0).isEmpty,
      "no session id can ever match a legacy 0 row: a session worker id is always > 0")
check([aOpen].forWorker(-1).isEmpty, "a nonsense id owns nothing")
check(!WorkerScope.owns(0, row: 0), "owns(0, row: 0) is false")
check(WorkerScope.owns(A, row: A) && !WorkerScope.owns(A, row: B), "owns is exact equality for real ids")

// Nothing here changes the store: the helpers return values, and the full store is intact.
check(sharedStore.count == 5, "scoping is a read - the device-wide outbox still holds all five rows")

// THE DEVICE-WIDE READ (P6): everybody's rows, in order, nothing filtered - and it is NOT a scoped list.
check(sharedStore.deviceWide() == sharedStore,
      "deviceWide() returns EVERY account's rows in the sequence's order: the outbox the delivery summary counts")
check(sharedStore.deviceWide().count == sharedStore.forWorker(A).count + sharedStore.forWorker(B).count + 2,
      "...which is A's, B's and the two legacy rows - strictly more than any one worker's list")

// Stale async work is dropped (Android re-checks the worker id after each read).
check(WorkerScope.isCurrent(A, session: A), "the same worker is current")
check(!WorkerScope.isCurrent(A, session: B), "a refresh that started for A is stale once B holds the session")
check(!WorkerScope.isCurrent(A, session: nil), "...and once nobody does: a refresh must not re-arm a signed-out phone")

// ---------------------------------------------------------------------------------
// 2. The screens, read as text
// ---------------------------------------------------------------------------------

func source(_ name: String) -> String { try! String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) }
func between(_ s: String, _ from: String, _ to: String) -> String {
    let after = s.components(separatedBy: from)
    guard after.count > 1 else { return "" }
    return after[1].components(separatedBy: to)[0]
}
/// Code lines only: comments and doc comments are where this rationale lives and must not trip a ban.
func codeLines(_ s: String) -> [(n: Int, line: String)] {
    s.components(separatedBy: "\n").enumerated().compactMap { i, l in
        l.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? nil : (i + 1, l)
    }
}

/// Comments stripped, so a rationale that quotes `arm(for: nil)` can never satisfy an assertion that the CODE has it.
func code(_ s: String) -> String { codeLines(s).map(\.line).joined(separator: "\n") }

let viewSource = source("ContentView.swift")
let materialsSource = source("MaterialsView.swift")
let view = code(viewSource)
let materialsView = code(materialsSource)
let auth = code(source("Auth.swift"))
let sync = code(source("Sync.swift"))
let app = code(source("NFCTimeSheetsApp.swift"))

check(app.contains("extension Shift: WorkerScoped {}"), "the Shift model conforms to WorkerScoped")

for (name, text) in [("ContentView.swift", viewSource), ("MaterialsView.swift", materialsSource)] {
    let lines = codeLines(text)

    // (a) every @Query over Shift is declared with the loud, device-wide name
    for (n, l) in lines where l.contains("@Query") && l.contains("[Shift]") {
        check(l.contains("var allShifts: [Shift]"),
              "\(name):\(n): a Shift @Query must be named allShifts (device-wide, read only through WorkerScope): \(l.trimmingCharacters(in: .whitespaces))")
    }

    // (b) every use of allShifts goes through the helper
    for (n, l) in lines where !l.contains("@Query") {
        var rest = Substring(l)
        while let r = rest.range(of: "allShifts") {
            let tail = rest[r.upperBound...]
            // `.deviceWide(` joined the list with P6 (decision-82): it is WorkerScope's own accessor and is held to
            // the two exact delivery-row lines below, so it can not become a way to list or toggle another account's rows.
            check(tail.hasPrefix(".forWorker(") || tail.hasPrefix(".openShift(for:") || tail.hasPrefix(".completed(for:")
                  || tail.hasPrefix(".deviceWide()"),
                  "\(name):\(n): allShifts is read without WorkerScope (forWorker / openShift(for:) / completed(for:) / deviceWide()): \(l.trimmingCharacters(in: .whitespaces))")
            rest = tail
        }
    }

    // (c) no raw open-shift read: the unscoped first(where: \.isOpen) is exactly the cross-worker toggle
    for (n, l) in lines {
        check(!l.contains("\\.isOpen") && !l.contains("$0.isOpen"),
              "\(name):\(n): a raw .isOpen read - an open-shift or open-row lookup must go through WorkerScope.openShift(for:): \(l.trimmingCharacters(in: .whitespaces))")
    }
}

// THE DEVICE-WIDE READ, held to its one purpose (P6). ContentView.swift reads `deviceWide()` in exactly two
// places - LogView's and SignInView's `deliveryRows` - and each result is only ever mapped to a PendingRow
// value. MaterialsView, History, the tab lock, the tap and the signals never see another account's rows.
let deviceWideLines = codeLines(viewSource).filter { $0.line.contains(".deviceWide(") }.map { $0.line.trimmingCharacters(in: .whitespaces) }
check(deviceWideLines.sorted() == ["allShifts.deviceWide().map { $0.deliveryRow(sessionWorkerId: worker.id) }",
                                   "private var deliveryRows: [PendingRow] { allShifts.deviceWide().map { $0.deliveryRow() } }"].sorted(),
      "deviceWide() appears in ContentView.swift only as the delivery summary's two inputs (got \(deviceWideLines))")
check(!materialsView.contains("deviceWide"), "MaterialsView never reads another account's rows")
check(!between(view, "struct HistoryView: View {", "struct SettingsView: View {").contains("deviceWide"),
      "History lists, totals and deletes only the signed-in worker's rows - never the device-wide outbox")
for (n, fn) in [("handleTap", between(view, "private func handleTap(", "\n    private func outcome(")),
                ("shiftRunning", between(view, "private func shiftRunning(", "\n")),
                ("currentRunning", between(view, "private func currentRunning()", "\n    }")),
                ("startManual", between(view, "private func startManual() {", "private func manualStop() {"))] {
    check(!fn.isEmpty && !fn.contains("deviceWide"), "\(n) never reads the device-wide outbox: a tap toggles THIS worker's row")
}

// The one place a signal is armed FROM is scoped. Both fetch-based and query-based reads.
let currentRunning = between(view, "private func currentRunning()", "\n    }")
check(currentRunning.contains("openShift(for: worker.id)"),
      "currentRunning() (what the badge, the ladder and the Live Activity are armed from) reads the SESSION worker's open row only")
check(currentRunning.contains("FetchDescriptor<Shift>"), "currentRunning() still reads the context, not @Query (the save-then-arm turn)")

// The lock, the running screen, the manual guard and the manual stop all use the scoped row.
check(view.contains("private func shiftRunning(for workerId: Int) -> Bool { allShifts.openShift(for: workerId) != nil }"),
      "the tab lock is the signed-in worker's open shift")
check(view.contains("ShiftSignal.visibleTabs(shiftRunning: shiftRunning(for: worker.id))"),
      "the lock is computed inside the .eligible branch, from the session's worker")
check(view.contains("private var openRow: Shift? { allShifts.openShift(for: worker.id) }"),
      "LogView's open row is THIS worker's newest open row")
// origin/main (shift evidence, PR 17) split manualStop in three: manualStop() is now only the hand-off,
// prepareCompletion() the proof gate and finishManualStop() the old close-the-local-row body. The
// assertion that was about manualStop's body moved with the code it was about, and the two new
// pieces are held to the same scope: BOTH read THIS worker's row (openRow), never the device-wide store.
check(between(view, "private func manualStop() {", "\n    }").contains("prepareCompletion(manual: true) { finishManualStop() }"),
      "manualStop hands the stop to the evidence gate, which then runs finishManualStop")
check(between(view, "private func finishManualStop() {", "\n    }").contains("openRow"),
      "finishManualStop closes this worker's row")
check(between(view, "private func prepareCompletion(", "\n    }").contains("openRow"),
      "the proof gate looks at this worker's row - another account's open row never starts a camera")
check(between(view, "private func startManual() {", "private func manualStop() {").contains("openRow != nil"),
      "the manual-start 'already open' answer is about THIS worker's open shift")
check(between(view, "private func handleTap(", "\n    private func outcome(").contains("if let running = openRow {"),
      "handleTap toggles THIS worker's open row (B's tap never closes A's)")
check(materialsView.contains("private var openShift: Shift? { allShifts.openShift(for: worker.id) }"),
      "the material request's building context is the signed-in worker's open shift")

// History: list, totals and swipe-delete are all the signed-in worker's.
let history = between(view, "struct HistoryView: View {", "struct SettingsView: View {")
check(history.contains("let worker: WireWorker") && view.contains("HistoryView(worker: worker)"),
      "HistoryView is built for the signed-in worker")
check(history.contains("private var mine: [Shift] { allShifts.forWorker(worker.id) }"), "History's rows are this worker's")
check(history.contains("allShifts.completed(for: worker.id)"), "History's totals are made of this worker's finished rows")
check(between(history, ".onDelete {", "}\n").contains("mine"), "a History swipe deletes from THIS worker's rows (index into `mine`)")

// Foreign rows are KEPT: the only context.delete in the screens is that swipe.
check(view.components(separatedBy: "context.delete").count - 1 == 1,
      "ContentView deletes rows in exactly one place (the History swipe, scoped to the worker)")
check(!materialsView.contains("context.delete"), "MaterialsView deletes nothing")
check(!auth.contains("ModelContext") && !auth.contains("FetchDescriptor"),
      "Session never touches the shift store: nothing is deleted on sign-out")
check(sync.components(separatedBy: "context.delete").count - 1 == 1 && sync.contains("context.delete(site)"),
      "the sync engine deletes no SHIFT rows (its one delete is a stale roster Site)")

// THE RESET ON A DIRECT WORKER CHANGE: .id(worker.id), first modifier on the TabView.
let tabView = view.range(of: "TabView(selection: $selection) {")
let tabId = view.range(of: ".id(worker.id)")
let tabEnv = view.range(of: ".environment(materials)")
let tabTask = view.range(of: ".task(id: worker.id) { await materials.start(workerId: worker.id) }")
check(tabView != nil && tabId != nil && tabEnv != nil && tabTask != nil, "the TabView, its .id, .environment and materials task all exist")
if let tabView, let tabId, let tabEnv, let tabTask {
    check(tabView.upperBound < tabId.lowerBound && tabId.upperBound <= tabEnv.lowerBound && tabEnv.upperBound < tabTask.lowerBound,
          "the TabView carries .id(worker.id) as its FIRST modifier, before .environment and the materials task")
    check(view[tabId.upperBound..<tabEnv.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          "nothing sits between the TabView's .id(worker.id) and the modifiers after it")
}
check(view.components(separatedBy: ".task(id: worker.id) { await materials.start(workerId: worker.id) }").count - 1 == 1,
      "the existing materials start task is still keyed on worker.id")

// TEARDOWN: sign-out and a rejected session share ONE teardown, and it takes the signals down.
let clear = between(auth, "private func clearLocalSession() {", "\n    }")
check(clear.contains("ShiftSignalCenter.shared.arm(for: nil)"),
      "Session.clearLocalSession tears the badge, the reminders and the Live Activity down (Android: ShiftSignals.arm(app, null))")
check(between(auth, "func signOut() async {", "\n    }").contains("clearLocalSession()"),
      "signOut goes through clearLocalSession")
check(between(auth, "private func serverRejectedSession() {", "\n    }").contains("clearLocalSession()"),
      "a 401 (serverRejectedSession) goes through clearLocalSession")
check(!between(view, "struct SignInView: View {", "struct LogView: View {").contains("ShiftSignalCenter"),
      "the signals are never torn down from the sign-in screen - that would race the next worker's arm")

// Roster caches are NOT cleared on a worker change: GET /roster is worker-independent (every
// active building and zone, server/routes/app.js roster()), so a colleague's cache leaks nothing,
// and clearing it would cost an OFFLINE phone its building names, the manual-start picker and the
// same-building rule on the TAP path. A cache miss is cosmetic; it must never become a gate.
check(!clear.contains("RosterZones") && !clear.contains("Site"), "sign-out leaves the roster caches alone (see above)")

// STALE ASYNC WORK IS DROPPED: a refresh that lands after sign-out or a worker change must not re-arm.
let armIf = between(view, "private func armIfStillCurrent() {", "\n    }")
check(armIf.contains("WorkerScope.isCurrent(worker.id, session: session.worker?.id)") && armIf.contains("signals.arm(for: currentRunning())"),
      "armIfStillCurrent arms only while this worker still holds the session")
check(between(view, "private func refresh() async {", "\n    }").contains("armIfStillCurrent()"),
      "refresh() ends in the guarded arm: five awaits is a long window for a sign-out")
check(between(view, "private func handleTap(", "\n    private func outcome(").contains("armIfStillCurrent()"),
      "handleTap's post-roster re-arm is the guarded one")

// THE TAP IS STILL UNGATED BY THE SESSION: nothing before the local save reads the session or asks
// WorkerScope.isCurrent. (The shift-evidence proof gate that origin/main put in front of a FINISH is
// pinned in shift-signal-check.swift: it reads openRow, never the session, so it passes this too.)
let tapToSave = between(view, "private func handleTap(", "try? context.save()")
check(!tapToSave.contains("session.") && !tapToSave.contains("isCurrent") && !tapToSave.contains("armIfStillCurrent"),
      "nothing waits on, or is refused by, the session between a tap and its local write")

// SYNC: the engine still sees ALL rows (the outbox is device-wide), and another account's close is
// never pushed under this cookie (it would 404 unknown_shift, which is terminal, and block the row).
check(between(sync, "func syncPending(", "\n}").contains("FetchDescriptor<Shift>(sortBy:") &&
      !between(sync, "func syncPending(", "\n}").contains("forWorker"),
      "syncPending keeps iterating ALL rows - the outbox is device-wide")
check(between(sync, "private func pushClose(", "do {").contains("guard shift.workerId == workerId else { return }"),
      "pushClose skips (without blocking) a row another account queued")
check(between(sync, "func syncPending(", "\n}").contains("pushClose(shift, end: end, as: workerId)"),
      "syncPending hands pushClose the session worker")

if failed { exit(1) }
print("worker-scope-check: OK")
