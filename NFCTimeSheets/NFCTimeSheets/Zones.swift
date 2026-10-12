//
//  Zones.swift
//  NFCTimeSheets
//
//  Pure decision logic for zones, ported from android/.../core/Zones.kt (decision-43,
//  decision-44, decision-47). Foundation-only so checks/zones-check.swift can run it on a
//  laptop. No network, no SwiftData, no UI.
//
//  WHAT A TAP POSTS IS A ZONE ID, AND EVERYTHING ELSE THE PHONE SHOWS OR COMPARES IS ABOUT
//  THE BUILDING. A worker's shift row keeps the id they tapped (a fact), so the building a
//  row belongs to has to be derived from the roster's zone list - [buildingIdOf] for the
//  comparison, [buildingName] for the label, [materialContext] for the one request the
//  server still validates against BUILDINGS only.
//
//  ONE COPY of each. A second hand-written serial normaliser is exactly the scar TagLink's
//  '+'-vs-space case already left in this codebase once (see TagLink.swift's header).
//

import Foundation

enum Zones {
    /// The BUILDING id a tapped place belongs to. The id space a tag carries is shared
    /// between buildings and zones: `placeId` may already be a building id, or a zone id that
    /// [zones] can resolve.
    ///
    /// IDENTITY ON A CACHE MISS, NEVER A SENTINEL - load-bearing, not a shortcut. A fresh
    /// install, an offline cold launch or a roster fetch that failed silently all leave
    /// [zones] empty or stale. Defaulting an unresolved id to a shared placeholder would
    /// treat every currently-uncached place as the SAME building the moment the cache is
    /// empty, and a worker tapping out at the wrong door would close a shift that was not
    /// theirs to close. Returning the id itself keeps two different unresolved places
    /// different, and a building id that resolves against nothing is already its own
    /// building id. NOTHING MAY GATE A TAP ON A CACHE HIT.
    ///
    /// Compared case-insensitively: a UUID is the same UUID in either case, and the id on a
    /// tag, the id the server echoes and the id in the cache are not guaranteed to agree on it.
    static func buildingIdOf(_ placeId: String, zones: [WireZone]) -> String {
        let key = placeId.lowercased()
        return zones.first { $0.id.lowercased() == key }?.locationId ?? placeId
    }

    /// The building's NAME for a shift's stored place id, or nil when it is not cached yet.
    /// `buildingNames` maps building id -> name (the cached Site rows). The caller falls back
    /// to "Unknown location"; nothing branches on this being nil.
    static func buildingName(of placeId: String, zones: [WireZone], buildingNames: [String: String]) -> String? {
        let want = buildingIdOf(placeId, zones: zones).lowercased()
        return buildingNames.first { $0.key.lowercased() == want }?.value
    }

    /// The building id to attach to a MATERIAL REQUEST for a shift started at [placeId].
    /// `POST /material-requests` validates `location_uuid` against active BUILDINGS only
    /// (server/lib/validate.js activeLocation), so a ZONE id answers 422 and the request
    /// stays blocked on the phone for ever. A request with no building is a perfectly good
    /// request, which is why the answer is nil, never a guess:
    ///   - a zone whose building is cached        -> that building
    ///   - a building id that is cached           -> itself
    ///   - anything else (cold cache, unknown id) -> nil
    /// NEVER returns a zone id.
    static func materialContext(of placeId: String, zones: [WireZone], knownBuildingIds: [String]) -> String? {
        let building = buildingIdOf(placeId, zones: zones)
        let known = Set(knownBuildingIds.map { $0.lowercased() })
        return known.contains(building.lowercased()) ? building : nil
    }

    /// The zone whose `tag_serial` matches a scanned hardware [serial], normalised on both
    /// sides so any casing or separator style a reader prints still matches. Returns the
    /// zone's PLACE id (never the building id): callers post that straight to the server,
    /// which resolves it itself (decision-44 §3: the serial never reaches the server).
    static func zonePlaceIdForSerial(_ serial: String?, zones: [WireZone]) -> String? {
        guard let normalised = normaliseSerial(serial) else { return nil }
        return zones.first { normaliseSerial($0.tagSerial) == normalised }?.id
    }

    /// Uppercase hex, colon-separated - the shape the server's `zones.tag_serial` column
    /// holds, and the shape a hardware UID has to be normalised into on BOTH sides before
    /// they can be compared. No serial ever travels TOWARDS the server (decision-44): this
    /// is used only to match a scanned UID against the worklist already on the phone.
    static func normaliseSerial(_ serial: String?) -> String? {
        guard let serial else { return nil }
        let cleaned = serial.uppercased().filter { $0.isHexDigit }
        guard !cleaned.isEmpty else { return nil }
        var chunks: [String] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let end = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            chunks.append(String(cleaned[index..<end]))
            index = end
        }
        return chunks.joined(separator: ":")
    }
}
