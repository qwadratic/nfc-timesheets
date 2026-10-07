//
//  FinishCard.swift
//  NFCTimeSheets
//
//  FINISHING A CARD THAT WAS WRITTEN AND REPORTED BUT NEVER MADE A ZONE (decision-76).
//
//  Test a tag finds such a card (`GET /operator/tags/:id` answers `tag_reported`) and the
//  operator turns it into a zone right there. This file is the ORDER of the two calls that
//  follow, and nothing else, so checks/finish-card-check.swift can pin it without a phone:
//
//    1. resolve-zone   - the card becomes a zone (name, and a building unless skipped).
//    2. verify         - ONLY when the zone came back with a building, and with the id the
//                        phone READ OFF THE CARD, which is the whole point: the scan that
//                        found the card is its test scan (decision-47), so the operator is
//                        not asked to prove the same bytes twice.
//
//  A zone without a building is never verified here: `activePlace` cannot resolve it, so
//  there is nothing for a scan to prove yet (decision-54 §7).
//
//  FOUNDATION-ONLY AND GENERIC ON PURPOSE. It never names WireCreatedZone or
//  WireZoneVerifyResult, so a check can drive it with two integers and a pair of closures.
//
//  A resolve failure is thrown to the caller: nothing was created, the screen says why and
//  the operator can try again. A VERIFY failure is NOT thrown: by then the zone exists, and
//  throwing would make the screen report "could not create" about a zone that was created.
//  It comes back as `.notVerified` instead, and the screen offers the ordinary test scan.
//  Nothing is rolled back and nothing is lost.
//

import Foundation

enum FinishCard {
    enum Outcome<Zone, Proof> {
        /// Created without a building. Not verified, on purpose.
        case unbound(Zone)
        /// Created with a building and proved by the scan that found the card.
        case verified(Zone, Proof)
        /// Created with a building, but the verify call failed. `code` is the server's error
        /// code, or "network" when there was none.
        case notVerified(Zone, code: String)
    }

    static func run<Zone, Proof>(
        isBound: (Zone) -> Bool,
        resolve: () async throws -> Zone,
        verify: (Zone) async throws -> Proof
    ) async throws -> Outcome<Zone, Proof> {
        let zone = try await resolve()
        guard isBound(zone) else { return .unbound(zone) }
        do {
            return .verified(zone, try await verify(zone))
        } catch let failure as APIFailure {
            return .notVerified(zone, code: failure.code)
        } catch {
            return .notVerified(zone, code: "network")
        }
    }
}
