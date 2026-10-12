// Runnable check: the server's answer never DOWNGRADES a local close flag (TASK-365.22 D1).
//
//   cd NFCTimeSheets && cat checks/sync-flags-check.swift > /tmp/sync-flags-check.swift \
//     && swift /tmp/sync-flags-check.swift
//
// WHY: Sync.swift's apply() is called with the OPEN's answer (pushOpen) as well as the close's.
// An open answers auto_closed=false / manual_close=false. A phone that was offline when the
// worker finished without a tag (manualClose = true) or walked to another building
// (autoClosed = true) still holds that LOCAL true when the open finally goes out, and the old
// plain assignment wiped it before pushClose read it: the close arrived unflagged, so a manual
// stop looked ordinary and a walk-away shift bypassed decision-10's confirmed-end rule.
// The rig (ops/ios-rig, walks bug-offline-manual-stop / bug-offline-switch) is the behavioural
// proof; this check keeps the two assignments from being "tidied" back.
//
// RED CASE reproduced before this was trusted: restoring `shift.autoClosed = wire.autoClosed`
// or `shift.manualClose = wire.manualClose ?? shift.manualClose` fails the matching line below.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

let sync = try! String(contentsOfFile: "NFCTimeSheets/Sync.swift", encoding: .utf8)
let apply = sync.components(separatedBy: "private func apply(_ wire: WireShift, to shift: Shift) {")[1]
    .components(separatedBy: "/// A failure ALWAYS leaves a message on the row.")[0]

check(apply.contains("shift.autoClosed = shift.autoClosed || wire.autoClosed"),
      "autoClosed is only ever raised by the server's answer")
check(apply.contains("shift.manualClose = shift.manualClose || (wire.manualClose ?? false)"),
      "manualClose is only ever raised by the server's answer")
check(!apply.contains("shift.autoClosed = wire.autoClosed"),
      "no plain overwrite of autoClosed from the server's answer")
check(!apply.contains("shift.manualClose = wire.manualClose"),
      "no plain overwrite of manualClose from the server's answer")
// manualStart keeps its own nil-tolerant rule (a start flag is never cleared by an older server).
check(apply.contains("shift.manualStart = wire.manualStart ?? shift.manualStart"),
      "manualStart keeps the nil-tolerant rule")

if failed { exit(1) }
print("sync-flags-check: OK")
