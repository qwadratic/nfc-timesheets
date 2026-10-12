//
//  RosterZones.swift
//  NFCTimeSheets
//
//  THE WORKER PHONE'S COPY OF THE ROSTER'S ZONES (decision-43), and why it exists: a tap
//  posts a ZONE id, the shift row keeps it, and until this file the phone had no idea which
//  building a zone belongs to. Every tap-started shift therefore read "Unknown location",
//  two zones of one building looked like two buildings (tapping out at the second door
//  auto-closed the shift as if the worker had walked away), and a material request carried a
//  zone id the server refuses. Android has had this since the zone model landed
//  (core/Zones.kt + the roster's zone cache); this is the port.
//
//  A LABEL AND A COMPARISON, NEVER A GATE. Nothing on the tap path waits for this or refuses
//  on a miss (Zones.buildingIdOf is identity on a miss, on purpose).
//
//  NOT A SwiftData @Model: a zone is a copy of one server answer, replaced WHOLESALE on every
//  successful GET /roster in the same pass as the Site rows, and a SwiftData migration for it
//  would put the unpushed-shift store one schema change away. One JSON snapshot in
//  UserDefaults, through the same Wire coder the live call uses - the precedent is
//  OperatorZoneCache, which is the OPERATOR's worklist and is deliberately not reused.
//
//  NOT cleared by decision-62's first-launch invalidation: the launch refetch replaces it.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RosterZones {
    static let shared = RosterZones()

    private static let key = "roster.zones.json"

    private(set) var zones: [WireZone]

    init() {
        zones = Self.read()
    }

    /// Replace the cache with a SUCCESSFUL roster answer. Never called on a failed fetch, so
    /// a phone with no signal keeps the last answer it had.
    func replace(with fresh: [WireZone]) {
        zones = fresh
        if let data = try? Wire.encoder.encode(fresh) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// The building name for a shift's stored place id, or nil when it is not known yet.
    func buildingName(of placeId: String, sites: [Site]) -> String? {
        Zones.buildingName(of: placeId, zones: zones, buildingNames: Self.names(of: sites))
    }

    /// The building to attach to a material request, or nil (decision-43; see Zones).
    func materialContext(of placeId: String, sites: [Site]) -> String? {
        Zones.materialContext(of: placeId, zones: zones, knownBuildingIds: sites.map(\.locationId))
    }

    private static func names(of sites: [Site]) -> [String: String] {
        Dictionary(sites.map { ($0.locationId, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private static func read() -> [WireZone] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let zones = try? Wire.decoder.decode([WireZone].self, from: data)
        else { return [] }
        return zones
    }
}
