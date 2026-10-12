// Runnable check: finishing a reported-but-never-zoned card (decision-76).
//
//   cd NFCTimeSheets && cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift \
//     NFCTimeSheets/API.swift NFCTimeSheets/FinishCard.swift checks/finish-card-check.swift \
//     > /tmp/finish-card-check.swift && swift /tmp/finish-card-check.swift
//
// WHAT HAPPENED, which is why this exists: on 2026-10-07 a card was written and reported on
// the staging server and the zone step never completed. The card stayed a reported tag with
// no zone and every tap of it answered 422 tag_unbound. Test a tag has to be able to finish
// it, and finishing has to leave a zone that workers can actually clock in on, in ONE visit.
//
// Pinned here: the ORDER (resolve, then verify), that a zone created without a building
// makes NO verify call, that a failure in the second call never turns into a failure of the
// first, and that a failed resolve never reaches a verify.
//
// WHAT THIS CANNOT PIN: which id the verify carries. That id is captured by the CLOSURE the
// screen passes in (VerifyZoneScreen.finishCard: `placeUuid: tagId`, the id read off the
// card), and FinishCard never sees it. The fake below stands in for that closure, so the
// "verify:CARD-ID..." entry proves the plumbing shape, not the screen's wiring. That wiring
// is read in review and driven on the Simulator.
//
// RED CASES, reproduced against mutated copies of FinishCard.swift before this was trusted
// (see the log in the commit message): calling resolve again after the verify fails "resolve
// comes before verify"; verifying a zone without a building fails "no verify call without a
// building"; attempting a verify after a failed resolve fails "verify is never attempted
// after a failed resolve".

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

struct FakeZone { let id: String; let bound: Bool }

final class Calls { var log: [String] = [] }

func exercise(bound: Bool, verifyFails: Error? = nil, resolveFails: Error? = nil)
    async -> (outcome: FinishCard.Outcome<FakeZone, String>?, thrown: Bool, log: [String])
{
    let calls = Calls()
    let scanned = "CARD-ID-READ-OFF-THE-CARD"
    do {
        let outcome = try await FinishCard.run(
            isBound: { $0.bound },
            resolve: {
                calls.log.append("resolve")
                if let resolveFails { throw resolveFails }
                return FakeZone(id: "ZONE-ID-FROM-THE-SERVER", bound: bound)
            },
            verify: { zone in
                calls.log.append("verify:\(scanned)")
                if let verifyFails { throw verifyFails }
                return "proof-for-\(zone.id)"
            })
        return (outcome, false, calls.log)
    } catch {
        return (nil, true, calls.log)
    }
}

// The async helper above needs a run loop for the script: a tiny blocking bridge.
func blocking<T>(_ work: @escaping () async -> T) -> T {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Task { box.value = await work(); done.signal() }
    done.wait()
    return box.value!
}
final class Box<T> { var value: T? }

// 1. A building was chosen: resolve THEN verify, and verify carries the scanned id.
let withBuilding = blocking { await exercise(bound: true) }
check(withBuilding.log == ["resolve", "verify:CARD-ID-READ-OFF-THE-CARD"],
      "resolve comes before verify (\(withBuilding.log))")
if case .verified(let zone, let proof)? = withBuilding.outcome {
    check(zone.id == "ZONE-ID-FROM-THE-SERVER" && proof == "proof-for-ZONE-ID-FROM-THE-SERVER",
          "the verified outcome carries the created zone and the proof")
} else {
    check(false, "a bound zone ends .verified")
}

// 2. Skip: no building, so nothing is verifiable and NO verify call is made.
let skipped = blocking { await exercise(bound: false) }
check(skipped.log == ["resolve"], "no verify call without a building (\(skipped.log))")
if case .unbound? = skipped.outcome {} else { check(false, "a zone without a building ends .unbound") }

// 3. Verify fails after the zone was created: NOT thrown, the zone is reported as created.
let refused = blocking { await exercise(bound: true, verifyFails: APIFailure(status: 422, code: "zone_mismatch")) }
check(!refused.thrown, "a verify failure never becomes a failure of the creation")
if case .notVerified(_, let code)? = refused.outcome {
    check(code == "zone_mismatch", "the server's own code is kept for the sentence (\(code))")
} else {
    check(false, "a failed verify ends .notVerified")
}
let offline = blocking { await exercise(bound: true, verifyFails: URLError(.notConnectedToInternet)) }
if case .notVerified(_, let code)? = offline.outcome {
    check(code == "network", "a transport failure reads as 'network' (\(code))")
} else {
    check(false, "a transport failure on verify ends .notVerified")
}

// 4. Resolve fails: thrown, and verify is NEVER attempted against a zone that does not exist.
let failedResolve = blocking { await exercise(bound: true, resolveFails: APIFailure(status: 409, code: "already_resolved")) }
check(failedResolve.thrown, "a resolve failure is thrown to the screen")
check(failedResolve.log == ["resolve"], "verify is never attempted after a failed resolve (\(failedResolve.log))")

if failed { exit(1) }
print("finish-card-check: OK")
