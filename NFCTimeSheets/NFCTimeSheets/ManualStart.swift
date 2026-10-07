//
//  ManualStart.swift
//  NFCTimeSheets
//
//  "START WITHOUT A TAG" PICKS A ZONE AND ASKS THE SERVER FIRST (decision-79, which amends
//  decision-56 §2/§4 and completes decision-69 for the worker phones). Ported from
//  android/.../ui/TimeSheetViewModel.kt `manualPlaces()` and ManualStartDialog.
//
//  WHY IT EXISTS. Since decision-69 a building id is no clock-in target: POST /shifts/open
//  with one is ALWAYS 422 `unknown_location`. iOS still offered the BUILDING list, wrote a
//  local running shift, and let the background sync discover the refusal - so the worker
//  saw a normal running screen for a shift the server never held, the stop was never sent
//  and the hours never arrived. The DEBUG mock echoed any id with a 201 and hid it.
//
//  TWO PURE DECISIONS, Foundation-only so checks/manual-start-check.swift can pin them:
//    - WHAT THE PICKER LISTS: cached roster zones whose building is cached, as
//      "<Building> · <Zone>", sorted, unverified zones included (the server answers a refusal
//      in words, which beats hiding the door), never a building.
//    - WHAT A FAILURE MEANS: a refusal is shown in the sheet and writes NOTHING; only a
//      transport failure, 408, 429 or 5xx falls back to iOS's local-first queue (the one
//      thing iOS does better than Android: a manual start still works in a basement).
//

import Foundation

enum ManualStart {
    struct Place: Equatable, Identifiable {
        let zoneId: String
        let buildingName: String
        let zoneName: String

        var id: String { zoneId }
        /// "<Building> · <Zone>". The separator is not language-specific, so it is not a key.
        var label: String { "\(buildingName) · \(zoneName)" }
    }

    /// The picker's rows. A zone whose BUILDING is not cached is left out rather than shown
    /// under a made-up name: the label would be wrong, and the sheet's empty state tells the
    /// worker to refresh. `buildingNames` maps building id -> name (the cached Site rows);
    /// ids compare case-insensitively.
    ///
    /// Sorted with `localizedStandardCompare` (building, then zone, then id so the order is
    /// stable). Android sorts by code point; the difference is cosmetic and accepted.
    static func places(zones: [WireZone], buildingNames: [String: String]) -> [Place] {
        let names = Dictionary(buildingNames.map { ($0.key.lowercased(), $0.value) },
                               uniquingKeysWith: { first, _ in first })
        return zones
            .compactMap { zone in
                names[zone.locationId.lowercased()].map {
                    Place(zoneId: zone.id, buildingName: $0, zoneName: zone.name)
                }
            }
            .sorted { a, b in
                let building = a.buildingName.localizedStandardCompare(b.buildingName)
                if building != .orderedSame { return building == .orderedAscending }
                let zone = a.zoneName.localizedStandardCompare(b.zoneName)
                if zone != .orderedSame { return zone == .orderedAscending }
                return a.zoneId < b.zoneId
            }
    }

    enum Disposition: Equatable {
        /// The server said no. Show it in the sheet; write no row.
        case refuse
        /// The server could not be asked (or could not answer yet). Fall back to the local
        /// queue, reusing the SAME client_uuid so the sync retry cannot open the shift twice.
        case queue
    }

    /// Every 4xx except 408 and 429 is the server's answer about THIS request: 409
    /// shift_already_open, 422 zone_unverified / unknown_location / tag_unbound, 401. Retrying
    /// them later would only produce a blocked row behind a normal-looking running screen,
    /// which is exactly the failure this file exists to end.
    static func classify(_ failure: APIFailure) -> Disposition {
        let status = failure.status
        if status == 0 || status == 408 || status == 429 || status >= 500 { return .queue }
        return .refuse
    }
}
