// Runnable check: the "Shift finished" receipt on the idle list (TASK-365.8, iOS P7, decision-83).
// Ported from Android at 60f6886 (TimeSheetApp.kt `showReceipt` / `CompletedShiftReceipt`,
// docs/ANDROID-WORKER-DESIGN.md "Final composition").
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/PendingWork.swift NFCTimeSheets/ShiftReceipt.swift checks/shift-receipt-check.swift \
//     > /tmp/shift-receipt-check.swift && swift /tmp/shift-receipt-check.swift
//
// WHAT THE FEATURE IS: after a finish the idle list shows a receipt - building, start-end, duration,
// the correction state and ONE delivery line - when the newest finished shift ended 0-120 s ago, and
// it STAYS until the worker presses Continue ("it does not disappear during reading"). It is inline,
// never a dialog, so taps, tabs and the resolver keep working.
//
// WHAT THIS CHECK GUARDS, in four parts, because each one is a way the receipt would quietly lie or
// vanish at the one moment somebody is reading it:
//   1. THE OFFER, run for real at fixed instants: only a finish 0-120 whole seconds old, captured
//      ONCE so it outlives the window, never offered again after Continue, a different row (or the
//      same row finished a second or more later) is a new offer, a relaunch after the window shows
//      nothing, a finish in the future is never offered - and the server echoing the finish time
//      back truncated to the millisecond is the SAME finish.
//   2. THE DELIVERY LINE, from the one predicate: an error sentence (red when nobody retries), "Sent",
//      "Sending..." inside the 2 s grace, "Saved on this phone" - and `isConfirmed`, the gate for
//      the check, which is a SEPARATE question: a delivered row that still needs its finish time
//      resolved says Sent and never plays.
//   3. THE PILLS: ShiftRow's chain for a finished row, in its order.
//   4. THE WIRING, read as text: the receipt is a Section after the unresolved banner and before the
//      delivery rows, the start Sections are drawn only without it, Recent loses its row, nothing
//      on the tap path or in the sync pass reads any of it, the view has no surface of its own, the
//      duration is fmtDur UNCHANGED, and both languages ship with Android's German verbatim.
//
// WHAT THIS CANNOT PIN: that the receipt looks right at 200% text, that Continue is not swallowed by
// the List row, that `.onChange(initial:)` fires when the idle list first appears after a finish.
// Those need a worker session on a device or simulator (TASK-365.22 is the rig that signs one in).
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

func source(_ name: String) -> String {
    guard let text = try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: cannot read NFCTimeSheets/\(name)\n".utf8))
        exit(1)
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
    let after = s.components(separatedBy: from)
    guard after.count > 1 else { return "" }
    return after[1].components(separatedBy: to)[0]
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

let t0 = Date(timeIntervalSince1970: 1_800_000_000)       // fixed, so nothing depends on "now"
func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

// ---------------------------------------------------------------------------------
// 1. THE OFFER
// ---------------------------------------------------------------------------------

check(ShiftReceipt.offerWindowSeconds == 120, "the offer window is two minutes (Android: seconds in 0..120)")
// A finish at t0; the question is asked `age` seconds later.
for age in [0.0, 0.5, 1, 60, 119, 120, 120.999] {
    check(ShiftReceipt.isRecent(endedAt: t0, now: at(age)), "a finish \(age) s ago is offered")
}
for age in [121.0, 121.5, 300, 3600, 86_400] {
    check(!ShiftReceipt.isRecent(endedAt: t0, now: at(age)), "a finish \(age) s ago is NOT offered")
}
for age in [-0.001, -0.5, -1, -60, -3600] {
    check(!ShiftReceipt.isRecent(endedAt: t0, now: at(age)),
          "a finish \(-age) s in the FUTURE (a phone clock behind the one that wrote it) is never offered (Java: -0.3 s is -1)")
}

func identity(_ uuid: String, _ end: Double) -> ShiftReceipt.Identity { ShiftReceipt.Identity(clientUuid: uuid, endedAt: at(end)) }
let A = identity("aaaa", 0)
let B = identity("bbbb", 3600)

do { // fresh finish: offered at once, captured, stays past the window, until Continue
    var memory = ShiftReceipt.Memory()
    check(memory.offer(for: A, now: at(5)) == A, "a finish 5 s old is offered with an EMPTY memory (the first frame shows it - no frame of the start controls)")
    memory.observe(A, now: at(5))
    check(memory.captured == A, "...and the offer is captured")
    check(memory.offer(for: A, now: at(130)) == A, "a captured receipt STAYS past the 120 s window (it is not dismissed while somebody reads it)")
    check(memory.offer(for: A, now: at(100_000)) == A, "...for as long as it takes: there is no timeout")
    memory.observe(A, now: at(130))
    check(memory.offer(for: A, now: at(131)) == A, "observing it again changes nothing")
    memory.dismiss(A)
    check(memory.offer(for: A, now: at(131)) == nil, "Continue dismisses it")
    memory.observe(A, now: at(132))
    check(memory.offer(for: A, now: at(132)) == nil, "a DISMISSED receipt is never re-offered, even by a later observation inside the window")
    check(memory.offer(for: A, now: at(10)) == nil, "...and not by asking at an earlier time either")
}
do { // an older finish seen for the first time after the window: never offered
    var memory = ShiftReceipt.Memory()
    check(memory.offer(for: A, now: at(121)) == nil, "a finish first seen at 121 s is not offered")
    memory.observe(A, now: at(121))
    check(memory.captured == nil && memory.offer(for: A, now: at(122)) == nil, "...and observing it captures nothing")
}
do { // a relaunch: the memory is gone and the window decides
    var before = ShiftReceipt.Memory()
    before.observe(A, now: at(10))
    let relaunched = ShiftReceipt.Memory()
    check(before.offer(for: A, now: at(500)) == A && relaunched.offer(for: A, now: at(500)) == nil,
          "a relaunch after 120 s shows nothing (a fresh memory); the running process keeps showing it")
    check(relaunched.offer(for: A, now: at(100)) == A, "a relaunch within the window shows it again")
}
do { // a different row is a new offer, and replaces the captured one
    var memory = ShiftReceipt.Memory()
    memory.observe(A, now: at(5))
    memory.dismiss(A)
    check(memory.offer(for: B, now: at(3605)) == B, "a different finished row is offered although A was dismissed")
    memory.observe(B, now: at(3605))
    check(memory.captured == B && memory.offer(for: A, now: at(3606)) == nil,
          "...the capture moves to B, and A (dismissed) stays out")
    memory.dismiss(B)
    check(memory.offer(for: B, now: at(3700)) == nil, "B's Continue dismisses B")
}
do { // a nil latest (no finished shift) offers nothing and changes nothing
    var memory = ShiftReceipt.Memory()
    memory.observe(A, now: at(5))
    memory.observe(nil, now: at(6))
    memory.dismiss(nil)
    check(memory.offer(for: nil, now: at(6)) == nil && memory.captured == A && memory.dismissed == nil,
          "no finished row offers nothing, and neither observing nor dismissing nil forgets or dismisses anything")
}

// IDENTITY: client_uuid + finish time, with 1 s of tolerance for the server's millisecond echo.
let sent = identity("cccc", 100.0004)           // what the phone wrote
let echoed = identity("cccc", 100.000)          // what apply() overwrote it with (truncated to ms)
check(sent == echoed, "the server's millisecond echo of the finish time is the SAME finish (a dismissed receipt does not come back)")
check(identity("cccc", 100) == identity("cccc", 100.999), "less than a second apart is the same finish")
check(identity("cccc", 100) != identity("cccc", 101), "a second or more apart is a different finish: the shift reopened and finished again")
check(identity("cccc", 100) != identity("dddd", 100), "another row at the same instant is another receipt")
do {
    var memory = ShiftReceipt.Memory()
    memory.observe(sent, now: at(101))
    memory.dismiss(sent)
    check(memory.offer(for: echoed, now: at(102)) == nil, "dismissed, then the ACK rewrites the finish time by a millisecond: still dismissed")
    check(memory.offer(for: identity("cccc", 160), now: at(161)) == identity("cccc", 160),
          "...but the same row finished again a minute later is a new receipt")
}

// ---------------------------------------------------------------------------------
// 2. THE DELIVERY LINE, and the gate for the check
// ---------------------------------------------------------------------------------

/// A finished row, defaulting to the most common shape: opened and closed on the phone, nothing sent.
func row(start: Double = 0, end: Double = 3600, open: Double? = nil, close: Double? = nil,
         blocked: Bool = false, owed: Bool = false) -> PendingRow {
    PendingRow(startTime: at(start), openSyncedAt: open.map(at), closeSyncedAt: close.map(at), isOpen: false,
               syncBlocked: blocked, finishOwed: owed, queuedByAnotherAccount: false, lastChangedAt: at(end))
}
let ended = 3600.0
func delivery(_ r: PendingRow, error: String? = nil, after seconds: Double) -> ShiftReceipt.Delivery {
    ShiftReceipt.delivery(row: r, syncError: error, now: at(ended + seconds))
}

check(delivery(row(open: 10, close: ended + 1), after: 5) == .sent, "the server has the open and the close: Sent")
check(delivery(row(open: 10, close: ended + 1), after: 100_000) == .sent, "...at any age")
check(delivery(row(), after: 0.5) == .sending, "an unanswered request inside the 2 s grace says Sending... - never 'not confirmed' for a normal online stop")
check(delivery(row(open: 10), after: 1.9) == .sending, "...also when only the close is outstanding")
check(delivery(row(), after: 2) == .savedLocally && delivery(row(), after: 30) == .savedLocally,
      "after the grace with no answer: 'Saved on this phone · not yet confirmed'")
check(delivery(row(), after: -5) == .savedLocally, "a clock that went backwards does not hold the row in 'Sending...' (the grace needs age >= 0)")
check(delivery(row(open: 10), after: 10) == .savedLocally, "the open landed, the close did not: saved on this phone, NOT 'Sent'")
check(delivery(row(close: ended + 1), after: 10) == .savedLocally, "a close with no acknowledged open is not delivered")
// A recorded problem wins over everything (Android: syncError first), in the error colour only when nobody retries it.
check(delivery(row(), error: "No connection - will send when you're back online.", after: 0.1)
      == .problem("No connection - will send when you're back online.", blocked: false),
      "a row's own sentence is shown as it is, even inside the grace")
check(delivery(row(blocked: true), error: "This location was removed. Ask your admin.", after: 50)
      == .problem("This location was removed. Ask your admin.", blocked: true),
      "a refused row says why, in the error colour (blocked)")
check(delivery(row(open: 10, close: ended + 1), error: "stale", after: 50) == .problem("stale", blocked: false),
      "a recorded problem is never hidden behind 'Sent'")
check(delivery(row(), error: "", after: 50) == .savedLocally, "an EMPTY error sentence is no error")
check(delivery(row(blocked: true), after: 50) == .savedLocally,
      "a refused row that somehow carries no sentence is still never 'Sent' (nor 'Sending...')")
check(delivery(row(open: 10, close: ended + 1, owed: true), after: 50) == .savedLocally,
      "a finish still owed with its proof is not delivered")

// isConfirmed: Android's `isFullySynced && syncError == null && !needsResolution` - the gate for the check.
let delivered = row(open: 10, close: ended + 1)
check(ShiftReceipt.isConfirmed(row: delivered, syncError: nil, needsResolution: false), "delivered, no error, nothing to resolve: confirmed")
check(ShiftReceipt.isConfirmed(row: delivered, syncError: "", needsResolution: false), "an empty error is no error")
check(!ShiftReceipt.isConfirmed(row: row(), syncError: nil, needsResolution: false), "QUEUED (nothing delivered) is never confirmed")
check(!ShiftReceipt.isConfirmed(row: row(open: 10), syncError: nil, needsResolution: false), "the close not delivered is never confirmed")
check(!ShiftReceipt.isConfirmed(row: row(blocked: true), syncError: "x", needsResolution: false), "BLOCKED is never confirmed")
check(!ShiftReceipt.isConfirmed(row: delivered, syncError: "Server trouble - will retry.", needsResolution: false), "a recorded problem is never confirmed")
check(!ShiftReceipt.isConfirmed(row: delivered, syncError: nil, needsResolution: true),
      "a delivered finish that still needs its time resolved is not celebrated")
check(!ShiftReceipt.isConfirmed(row: row(open: 10, close: ended + 1, owed: true), syncError: nil, needsResolution: false),
      "a finish owed with a proof is not confirmed")
// ...and the TWO QUESTIONS are separate: that same row says 'Sent' on its line.
check(delivery(delivered, after: 5) == .sent && !ShiftReceipt.isConfirmed(row: delivered, syncError: nil, needsResolution: true),
      "a delivered row that needs resolution reads 'Sent' (what the server has) and does not play (may the check play)")
// Every shape that is not delivered is a line that is not 'Sent' and a gate that is closed.
for (name, r) in [("nothing sent", row()), ("close owed", row(open: 10)), ("open owed", row(close: 5)),
                  ("blocked", row(blocked: true)), ("proof owed", row(open: 10, close: 5, owed: true))] {
    check(delivery(r, after: 30) != .sent && !ShiftReceipt.isConfirmed(row: r, syncError: nil, needsResolution: false),
          "\(name): the line is not 'Sent' and the check is not allowed")
}

// ---------------------------------------------------------------------------------
// 3. THE PILLS
// ---------------------------------------------------------------------------------

check(ShiftReceipt.badges(manualStart: false, manualClose: false, autoClosed: false, correctedAt: nil) == [],
      "an ordinary tapped finish has no pill")
check(ShiftReceipt.badges(manualStart: true, manualClose: false, autoClosed: false, correctedAt: nil) == [.manual]
      && ShiftReceipt.badges(manualStart: false, manualClose: true, autoClosed: false, correctedAt: nil) == [.manual],
      "either manual half is Manual (decision-56 section 5)")
check(ShiftReceipt.badges(manualStart: false, manualClose: true, autoClosed: false, correctedAt: at(1)) == [.manual, .corrected],
      "a manual stop is Manual + Corrected (the server stamps corrected_at in the same update)")
check(ShiftReceipt.badges(manualStart: false, manualClose: false, autoClosed: true, correctedAt: nil) == [.autoClosed],
      "closed by a walk-away or the timer and not yet confirmed is Auto-closed")
check(ShiftReceipt.badges(manualStart: false, manualClose: false, autoClosed: true, correctedAt: at(1)) == [.corrected],
      "...and Corrected once somebody confirmed the time")
check(ShiftReceipt.badges(manualStart: false, manualClose: false, autoClosed: false, correctedAt: at(1)) == [.corrected],
      "a correction stamp alone is Corrected")

// ---------------------------------------------------------------------------------
// 4. THE WIRING, read as text
// ---------------------------------------------------------------------------------

let logic = code(source("ShiftReceipt.swift"))
let view = code(source("ShiftReceiptView.swift"))
let content = code(source("ContentView.swift"))

check(logic.contains("import Foundation") && !logic.contains("import SwiftUI") && !logic.contains("import SwiftData") && !logic.contains("import UIKit"),
      "ShiftReceipt.swift is Foundation-only (the check runs it on a Mac with no Xcode)")
check(!logic.contains("UserDefaults") && !logic.contains("FileManager") && !logic.contains("@AppStorage") && !logic.contains("@SceneStorage")
      && !logic.contains("ModelContext") && !logic.contains("syncPending") && !logic.contains("handleTap"),
      "the receipt's rule persists nothing and reaches no tap or sync: a value in, a verdict out")
check(logic.contains("PendingWork.state(of: row) == .delivered") && logic.contains("PendingWork.isInFlight(row, now: now)"),
      "the delivery line and the gate ask PendingWork's one predicate (delivered / in flight), not a second definition")
check(!logic.contains("isFullySynced") && !logic.contains("openSyncedAt") && !logic.contains("closeSyncedAt"),
      "...and never re-derive 'is it delivered' from the raw fields")

// PLACEMENT. Top of the idle list: after the unresolved banner, before the delivery rows, the plan and Recent.
let idle = between(content, "private var idleList: some View {", "#if DEBUG\n            manualMockSection")
check(inOrder(idle, ["if !unresolved.isEmpty {", "if let receiptShift {", "ShiftReceiptView(shift: receiptShift, name: siteName(receiptShift.locationId)) {",
                     "receiptMemory.dismiss(receiptShift.receiptIdentity)", "DeliveryStatusRows(rows: deliveryRows, signedOut: false)",
                     "ScheduleSummary(", "Section(\"Recent\") {"]),
      "idle: the receipt sits after the unresolved banner and before the delivery rows, the plan and Recent")
check(inOrder(idle, ["Section(\"Recent\") {", "ForEach(recentRows)", "if receiptShift == nil {", "Button(action: scan) {", "Button(\"Start without a tag\") {"]),
      "idle: Recent shows recentRows (minus the receipt's row) and the scan block and 'Start without a tag' are drawn only with no receipt")
check(count(idle, "if receiptShift == nil {") == 1 && count(idle, "Button(action: scan)") == 1 && count(idle, "Button(\"Start without a tag\")") == 1,
      "one gate, and it covers exactly the two start Sections")
let afterGate = idle.components(separatedBy: "if receiptShift == nil {")[1]
check(afterGate.contains("Button(action: scan) {") && afterGate.contains("Button(\"Start without a tag\") {"),
      "both the scan button and the manual start are INSIDE that gate")
check(content.contains("            .onChange(of: recent.first?.receiptIdentity, initial: true) { _, latest in")
      || content.contains("        .onChange(of: recent.first?.receiptIdentity, initial: true) { _, latest in"),
      "the offer is captured when the newest finished row appears or changes (initial: true for the first appearance)")
check(count(content, "receiptMemory.observe(") == 1 && count(content, "receiptMemory.dismiss(") == 1 && count(content, "receiptMemory.offer(") == 1,
      "the memory is observed, dismissed and asked in exactly one place each")
check(content.contains("@State private var receiptMemory = ShiftReceipt.Memory()"), "the memory is the screen's own @State (dies with it, never persisted)")
check(content.contains("guard let latest = recent.first,\n              receiptMemory.offer(for: latest.receiptIdentity, now: .now) != nil else { return nil }\n        return latest"),
      "the receipt is for the NEWEST finished row of THIS worker (`recent` is WorkerScope.completed(for:)), and only while offered")
check(content.contains("private var recent: [Shift] { Array(allShifts.completed(for: worker.id).prefix(5)) }"),
      "`recent` is still the signed-in worker's finished rows (the receipt can never be another account's)")
check(content.contains("return recent.filter { $0.clientUuid != shown.clientUuid }"), "Recent drops the receipt's row, by client_uuid")
check(content.contains("if receiptShift == nil || !recentRows.isEmpty {"),
      "a Recent header is not drawn over nothing while the receipt shows the only finished row")
// INLINE, never a dialog.
for banned in [".sheet(", ".alert(", ".confirmationDialog(", ".fullScreenCover(", ".popover("] {
    check(!view.contains(banned), "ShiftReceiptView.swift is inline: no \(banned) (a modal would block a tag tap, the tabs and the resolver)")
}
check(!between(idle, "if let receiptShift {", "DeliveryStatusRows(").contains("sheet"), "...and LogView presents the receipt as a List Section")

// THE VIEW: no surface of its own, shared pills, fmtDur unchanged, explicit button style.
for banned in [".background(", ".listRow", "RoundedRectangle", "Capsule(", ".clipShape", ".cornerRadius", ".shadow(", "Color(", "Color.",
               ".overlay(", ".border(", "UIColor", ".foregroundColor(", ".fill(", ".stroke("] {
    check(!view.contains(banned),
          "ShiftReceiptView.swift has no hard-coded surface (found '\(banned)'): the Blue Hour reskin restyles the container and the shared pill")
}
let styles = view.components(separatedBy: ".foregroundStyle(").dropFirst().map { $0.components(separatedBy: ")")[0] }
check(!styles.isEmpty && styles.allSatisfy { [".secondary", "blocked ? .red : .orange", ".green"].contains($0) },
      "only semantic state colours are used (\(styles))")
check(view.contains("pill(\"Manual\", .blue)") && view.contains("pill(\"Corrected\", .purple)") && view.contains("pill(\"Auto-closed\", .red)"),
      "the pills are the shared `pill` with ShiftRow's colours")
check(view.contains("fmtDur(duration)") && content.contains("func fmtDur(_ s: TimeInterval) -> String { \"\\(Int(s) / 3600)h \\((Int(s) % 3600) / 60)m\" }"),
      "the duration is fmtDur, and fmtDur is UNCHANGED (LegacyClassifier and the migration receipt depend on its spelling)")
check(view.contains("Button(action: onContinue) {") && view.contains(".buttonStyle(.borderedProminent)") && view.contains("Text(\"Continue\").frame(maxWidth: .infinity)"),
      "Continue is one explicitly styled, full-width button (a default Button swallows a whole List row)")
check(inOrder(view, ["Text(\"Shift finished\")", "Text(verbatim: name)", "formatted(date: .omitted, time: .shortened)", "fmtDur(duration)",
                     "badges", "DeliveryLine(delivery: ShiftReceipt.delivery(row: row, syncError: shift.syncError, now: .now))", "Button(action: onContinue) {"]),
      "the receipt reads: heading, building, range, duration, pills, ONE delivery line, Continue")
check(count(view, "DeliveryLine(") == 1, "exactly one delivery line")
check(!view.contains("? Text(") && !view.contains("Text(delivery ==") && !view.contains("Label(delivered ?"),
      "no ternary of two string literals (the verbatim initialiser ships English, TASK-298)")
check(view.contains("Text(verbatim: name)") && view.contains("Text(verbatim: sentence)"),
      "the building and the row's already-localised sentence are DATA: verbatim, never looked up again")
let lineView = between(view, "private struct DeliveryLine: View {", "\n}\n")
check(inOrder(lineView, ["case .problem(let sentence, let blocked):", "case .sent:", "Label(\"Sent\"", "case .sending:", "Label(\"Sending…\"",
                         "case .savedLocally:", "Label(\"Saved on this phone · not yet confirmed\""]),
      "the delivery line is a switch of the four states, in words that are the existing keys")
check(inOrder(view, ["let row = shift.deliveryRow()", "ShiftReceipt.isConfirmed(row: row, syncError: shift.syncError, needsResolution: needsResolution)"])
      && view.contains("let needsResolution = shift.autoClosed && shift.correctedAt == nil"),
      "the gate and the line are read off the Shift row itself in body - never a copy captured a render earlier")

// STRINGS: both languages, Android's German verbatim.
let catalogue = try! JSONSerialization.jsonObject(with: Data(source("Localizable.xcstrings").utf8)) as! [String: Any]
let strings = catalogue["strings"] as! [String: Any]
func german(_ key: String) -> String? {
    (((((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["de"]) as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
}
func androidString(_ name: String) -> String? {
    guard let xml = try? String(contentsOfFile: "../android/app/src/main/res/values/strings.xml", encoding: .utf8) else { return nil }
    let open = "<string name=\"\(name)\">"
    guard let start = xml.range(of: open), let end = xml.range(of: "</string>", range: start.upperBound..<xml.endIndex) else { return nil }
    return String(xml[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "\\'", with: "'")
}
for (key, androidName) in [("Shift finished", "worker_receipt_title"), ("Continue", "worker_receipt_done"),
                           ("Saved on this phone · not yet confirmed", "worker_saved_locally"), ("Sent", "sync_sent"),
                           ("In progress", "status_running"), ("Corrected", "status_corrected")] {
    check(german(key) != nil && german(key) == androidString(androidName),
          "'\(key)' has Android's German '\(androidString(androidName) ?? "?")' verbatim (\(androidName)); got '\(german(key) ?? "nil")'")
}
// 'Auto-closed' is deliberately NOT in the list above: the pill's German has always been the abbreviated
// "Autom. beendet" (a pill is narrow) and this package reuses the key, it does not retranslate it.
check(german("Auto-closed") != nil, "the reused 'Auto-closed' pill key is in the catalogue")
check(german("%@ \u{2013} %@") == "%1$@ \u{2013} %2$@" && androidString("worker_receipt_range") == "%1$s \u{2013} %2$s",
      "the range key is '%@ – %@' (a spaced en dash) with positional markers in German, like Android's worker_receipt_range")
check(view.contains("Text(\"\\(shift.startTime.formatted(date: .omitted, time: .shortened)) \u{2013} \\(end.formatted(date: .omitted, time: .shortened))\")"),
      "the range literal in the view is the catalogue key to the character (en dash)")
check(german("Sending…") == "Wird gesendet …", "'Sending…' is the existing German key the in-flight line reuses")
check(german("Manual") != nil && german("Unknown location") == androidString("unknown_location"),
      "the reused keys are in the catalogue ('Unknown location' is Android's unknown_location verbatim: Objekt)")

if failed { exit(1) }
print("shift-receipt-check: OK")
