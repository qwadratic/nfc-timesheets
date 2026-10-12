// Runnable check: "Start without a tag" (decision-81).
//
//   cd NFCTimeSheets && cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift \
//     NFCTimeSheets/API.swift NFCTimeSheets/AppLanguage.swift NFCTimeSheets/ManualStart.swift checks/manual-start-check.swift \
//     > /tmp/manual-start-check.swift && swift /tmp/manual-start-check.swift
//
// WHY: since decision-69 a BUILDING id is never a clock-in target, but iOS's manual start offered
// the building list, wrote a local running shift and found out about the 422 in the background.
// The worker saw a normal running screen for a shift the server never held; the hours never
// arrived. Android fixed it in PR 7 (zone picker, ask the server first). This pins the picker's
// rows, the refuse/queue split, and - as text - that the screen asks BEFORE it writes and never
// writes on a refusal.
//
// RED CASES reproduced before this was trusted (see the commit): a picker fed from Site ids
// fails "never offers a building"; a refusal that still calls handleTap fails "a refusal writes
// no row"; asking the server AFTER the local write fails "the server is asked before any row".

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

let bHoiv = "b0000000-0000-4000-8000-000000000001"
let bSarai = "b0000000-0000-4000-8000-000000000002"
let bUncached = "b0000000-0000-4000-8000-000000000003"
func zone(_ id: String, _ building: String, _ name: String, serial: String? = nil) -> WireZone {
    WireZone(id: id, locationId: building, name: name, tagSerial: serial)
}
let names = [bHoiv: "HOIV", bSarai: "Sarai"]

// ---------------------------------------------------------------------------------
// 1. The picker's rows
// ---------------------------------------------------------------------------------

let zones = [
    zone("z3", bSarai, "shed"),
    zone("z1", bHoiv, "reception"),
    zone("z2", bHoiv, "4 floor", serial: "04:A1"),
    zone("z4", bUncached, "ghost"),            // building not cached
]
let places = ManualStart.places(zones: zones, buildingNames: names)

check(places.map(\.zoneId) == ["z2", "z1", "z3"], "sorted by building then zone, the uncached building's zone left out (\(places.map(\.zoneId)))")
check(places.map(\.label) == ["HOIV · 4 floor", "HOIV · reception", "Sarai · shed"], "labels read '<Building> · <Zone>' (\(places.map(\.label)))")
check(places.contains { $0.zoneId == "z1" }, "an UNVERIFIED zone (no serial) is offered: the server answers a refusal in words, which beats hiding the door")
let offered = Set(places.map(\.zoneId))
check(offered.isDisjoint(with: [bHoiv, bSarai]), "the picker never offers a building id")
check(ManualStart.places(zones: [], buildingNames: names).isEmpty, "no zones cached: empty (the sheet says refresh)")
check(ManualStart.places(zones: zones, buildingNames: [:]).isEmpty, "no buildings cached: empty, never zones under a made-up name")
check(ManualStart.places(zones: [zone("z9", bHoiv.uppercased(), "x")], buildingNames: names).count == 1, "building ids compare case-insensitively")
check(ManualStart.places(zones: [zone("b", bHoiv, "same"), zone("a", bHoiv, "same")], buildingNames: names).map(\.zoneId) == ["a", "b"],
      "identical names order by id, so the list is stable between refreshes")
check(ManualStart.places(zones: [zone("z10", bHoiv, "Stiege 10"), zone("z2", bHoiv, "Stiege 2")], buildingNames: names).map(\.zoneId) == ["z2", "z10"],
      "numbers sort numerically (Stiege 2 before Stiege 10)")

// ---------------------------------------------------------------------------------
// 2. Refuse or queue
// ---------------------------------------------------------------------------------

for (status, code) in [(409, "shift_already_open"), (422, "zone_unverified"), (422, "unknown_location"),
                       (422, "tag_unbound"), (401, "no_session"), (400, "invalid_uuid"), (404, "not_found")] {
    check(ManualStart.classify(APIFailure(status: status, code: code)) == .refuse, "\(status) \(code) is REFUSED: shown in the sheet, no row")
}
for (status, code) in [(0, "network"), (408, "timeout"), (429, "too_many_attempts"), (500, "http_500"), (503, "http_503")] {
    check(ManualStart.classify(APIFailure(status: status, code: code)) == .queue, "\(status) \(code) falls back to the local queue")
}

// ---------------------------------------------------------------------------------
// 3. THE SCREEN, read as text: it asks BEFORE it writes, and a refusal writes nothing
// ---------------------------------------------------------------------------------

let view = try! String(contentsOfFile: "NFCTimeSheets/ContentView.swift", encoding: .utf8)
let startManual = view.components(separatedBy: "private func startManual() {")[1]
    .components(separatedBy: "/// decision-56 §4/§3. Closes the LOCAL row first")[0]

let ask = startManual.range(of: "ShiftFlowAPI.open(")
let firstWrite = startManual.range(of: "handleTap(")
check(ask != nil, "startManual asks the server (ShiftFlowAPI.open)")
check(firstWrite != nil && ask!.upperBound <= firstWrite!.lowerBound,
      "the server is asked before any row is written")
check(startManual.contains("manual: true"), "the request carries manual: true")

let refuseBranch = startManual.components(separatedBy: "case .refuse:")[1]
    .components(separatedBy: "case .queue:")[0]
check(!refuseBranch.contains("handleTap("), "a refusal writes no row")
check(refuseBranch.contains("workerMessage"), "a refusal is shown in the worker's words")

check(startManual.contains("shift_already_open"), "an already-open shift is answered inline, without a request")
check(startManual.components(separatedBy: "handleTap(").count - 1 >= 2 &&
      startManual.components(separatedBy: "clientUuid: clientUuid").count - 1 >= 2,
      "the local-first fallback REUSES the same client_uuid, so the sync retry cannot open the shift twice")

check(!view.contains("pickableSites"), "the building-fed picker (pickableSites) is gone")
check(view.contains("ForEach(manualPlaces)"), "the picker is built from manualPlaces (zones)")

if failed { exit(1) }
print("manual-start-check: OK")
