// Runnable check: zones on the worker phone (decision-43, decision-47).
//
//   cd NFCTimeSheets && cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift \
//     NFCTimeSheets/API.swift NFCTimeSheets/AppLanguage.swift NFCTimeSheets/Zones.swift checks/zones-check.swift \
//     > /tmp/zones-check.swift && swift /tmp/zones-check.swift
//
// WHY: a tap posts a ZONE id and the shift row keeps it, but until this check existed the
// phone had no way to tell which BUILDING a zone is in. Three visible failures followed:
// every tap-started shift read "Unknown location"; tapping out at the building's SECOND door
// auto-closed the shift as if the worker had walked away; and a material request carried a
// zone id that the server (which validates against buildings only) answers 422 for ever.
// Mirrors android/checks/core-check.kt's Zones section (buildingIdOf, zonePlaceIdForSerial)
// so the two phones cannot disagree about what a place is.
//
// The wiring (handleTap, the foreground refresh, MaterialsView) is pinned as text in
// checks/shift-signal-check.swift, next to the rest of "the tap is never blocked".

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

func roster(_ json: String) -> WireRoster? {
    try? Wire.decoder.decode(WireRoster.self, from: Data(json.utf8))
}

let building = "b0000000-0000-4000-8000-000000000001"
let other = "b0000000-0000-4000-8000-000000000002"
let zoneA = "a0000000-0000-4000-8000-00000000000a"
let zoneB = "a0000000-0000-4000-8000-00000000000b"
let zoneC = "a0000000-0000-4000-8000-00000000000c"

let locationsJSON = """
"locations":[{"id":"\(building)","slug":"b1","name":"HOIV"},{"id":"\(other)","slug":"b2","name":"Sarai"}]
"""

// ---------------------------------------------------------------------------------
// 1. The roster decode. Zones are the LEAST strict field: they may never cost the locations.
// ---------------------------------------------------------------------------------

let full = roster("""
{\(locationsJSON),"zones":[
 {"id":"\(zoneA)","location_id":"\(building)","name":"4 floor","tag_serial":null},
 {"id":"\(zoneB)","location_id":"\(building)","name":"reception","tag_serial":"04:A1:B2:C3"}
],"workers":[]}
""")
check(full?.zones.count == 2 && full?.locations.count == 2, "a normal roster decodes both lists (\(String(describing: full?.zones.count)))")
check(full?.zones[0].tagSerial == nil, "a null tag_serial (an unverified zone) decodes to nil")
check(full?.zones[1].tagSerial == "04:A1:B2:C3", "a verified zone keeps its serial")
check(full?.zones[0].locationId == building, "location_id is the BUILDING")

let noKey = roster("{\(locationsJSON)}")
check(noKey != nil && noKey!.zones.isEmpty && noKey!.locations.count == 2,
      "a server too old to send `zones` is an empty list, and the locations survive")

let nullZones = roster("{\(locationsJSON),\"zones\":null}")
check(nullZones != nil && nullZones!.zones.isEmpty && nullZones!.locations.count == 2,
      "zones: null is an empty list, not a failed roster")

let wrongType = roster("{\(locationsJSON),\"zones\":\"nope\"}")
check(wrongType != nil && wrongType!.zones.isEmpty && wrongType!.locations.count == 2,
      "zones of the wrong type is an empty list, not a failed roster")

let oneBad = roster("""
{\(locationsJSON),"zones":[
 {"id":"\(zoneA)","location_id":"\(building)","name":"4 floor","tag_serial":null},
 {"id":"broken-row-with-no-building","name":"x"},
 {"id":"\(zoneB)","location_id":"\(building)","name":"reception","tag_serial":null,"extra":"ignored"}
]}
""")
check(oneBad != nil && oneBad!.locations.count == 2, "one malformed zone never costs the locations")
check(oneBad?.zones.map(\.id) == [zoneA, zoneB], "ONE malformed zone is dropped and the others stay (\(String(describing: oneBad?.zones.map(\.id))))")

check(roster("{\"zones\":[]}") == nil, "a roster with no locations still FAILS: that is a real error, not a degrade")

// ---------------------------------------------------------------------------------
// 2. buildingIdOf - mirrors android/checks/core-check.kt
// ---------------------------------------------------------------------------------

let zones = [
    WireZone(id: zoneA, locationId: building, name: "4 floor", tagSerial: nil),
    WireZone(id: zoneB, locationId: building, name: "reception", tagSerial: "04:A1:B2:C3"),
    WireZone(id: zoneC, locationId: other, name: "shed", tagSerial: nil),
]

check(Zones.buildingIdOf(zoneA, zones: zones) == building, "a zone resolves to its building")
check(Zones.buildingIdOf(building, zones: zones) == building, "a building id is its own building")
check(Zones.buildingIdOf("unknown-1", zones: zones) == "unknown-1", "a miss is IDENTITY, never a sentinel")
check(Zones.buildingIdOf("unknown-1", zones: []) == "unknown-1", "an EMPTY cache (cold launch, offline) is identity too")
check(Zones.buildingIdOf("unknown-1", zones: zones) != Zones.buildingIdOf("unknown-2", zones: zones),
      "two DIFFERENT misses stay different buildings - a shared placeholder would treat them as one and close a shift that was not the worker's to close")
check(Zones.buildingIdOf(zoneA.uppercased(), zones: zones) == building, "ids compare case-insensitively")
check(Zones.buildingIdOf(zoneA, zones: zones) == Zones.buildingIdOf(zoneB, zones: zones),
      "THE BUG: two zones of one building are ONE building, so the tap-out at the second door closes the shift")
check(Zones.buildingIdOf(zoneA, zones: zones) != Zones.buildingIdOf(zoneC, zones: zones),
      "zones of different buildings stay different, so a real switch still switches")

// ---------------------------------------------------------------------------------
// 3. buildingName - what every list shows
// ---------------------------------------------------------------------------------

let names = [building: "HOIV", other: "Sarai"]
check(Zones.buildingName(of: zoneA, zones: zones, buildingNames: names) == "HOIV", "a zone shows its building's name, not 'Unknown location'")
check(Zones.buildingName(of: building, zones: zones, buildingNames: names) == "HOIV", "a building id shows its name")
check(Zones.buildingName(of: zoneC, zones: zones, buildingNames: names) == "Sarai", "a zone of the other building shows that one")
check(Zones.buildingName(of: "unknown-1", zones: zones, buildingNames: names) == nil, "a miss is nil (the caller shows 'Unknown location')")
check(Zones.buildingName(of: zoneA, zones: [], buildingNames: names) == nil, "no zones cached and a zone id: nil, never a wrong building")
check(Zones.buildingName(of: zoneA, zones: zones, buildingNames: [:]) == nil, "the building itself not cached: nil")
check(Zones.buildingName(of: zoneA, zones: zones, buildingNames: [building.uppercased(): "HOIV"]) == "HOIV", "building ids compare case-insensitively here too")

// ---------------------------------------------------------------------------------
// 4. materialContext - the one request the server validates against BUILDINGS only
// ---------------------------------------------------------------------------------

let knownBuildings = [building, other]
check(Zones.materialContext(of: zoneA, zones: zones, knownBuildingIds: knownBuildings) == building,
      "a zone-started shift attaches its BUILDING to a material request")
check(Zones.materialContext(of: building, zones: zones, knownBuildingIds: knownBuildings) == building, "a building id attaches itself")
check(Zones.materialContext(of: "unknown-1", zones: zones, knownBuildingIds: knownBuildings) == nil, "an unknown id attaches nothing")
check(Zones.materialContext(of: zoneA, zones: [], knownBuildingIds: knownBuildings) == nil,
      "a zone id with no zones cached attaches NOTHING - sending the zone id is the 422 that blocks the row for ever")
check(Zones.materialContext(of: zoneA, zones: zones, knownBuildingIds: []) == nil, "a building that is not cached attaches nothing")
let everyPlace = [zoneA, zoneB, zoneC, building, other, "unknown-1"]
for place in everyPlace {
    let context = Zones.materialContext(of: place, zones: zones, knownBuildingIds: knownBuildings)
    check(context == nil || knownBuildings.contains(context!), "materialContext(\(place.prefix(8))) is nil or a known BUILDING, never a zone id")
}

// ---------------------------------------------------------------------------------
// 5. zonePlaceIdForSerial - mirrors android/checks/core-check.kt
// ---------------------------------------------------------------------------------

check(Zones.zonePlaceIdForSerial("04a1b2c3", zones: zones) == zoneB, "a serial matches whatever casing and separators the reader printed")
check(Zones.zonePlaceIdForSerial("04:a1:b2:c3", zones: zones) == zoneB, "colon-separated lower case matches too")
check(Zones.zonePlaceIdForSerial("DE:AD:BE:EF", zones: zones) == nil, "an unknown serial matches nothing")
check(Zones.zonePlaceIdForSerial(nil, zones: zones) == nil, "no serial matches nothing")
check(Zones.zonePlaceIdForSerial("", zones: zones) == nil, "an empty serial matches nothing (it must not match the zones that have NO serial)")

if failed { exit(1) }
print("zones-check: OK")
