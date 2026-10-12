//
//  VersionTapGate.swift
//  NFCTimeSheets
//
//  THE OPERATOR DOOR'S RULE: five taps on the version line open the operator gate, then the
//  sequence starts again. Ported clause for clause from android/.../core/VersionTapGate.kt at
//  60f6886 (checked there by android/checks/version-tap-gate-check.kt, and here by
//  checks/version-tap-gate-check.swift):
//
//    - EXACTLY five taps (`requiredTaps`);
//    - taps one to four open nothing and show nothing;
//    - the counter resets ONLY on the fifth, which opens the operator gate;
//    - there is NO time window: four taps and a coffee are still four taps.
//
//  PURE AND FOUNDATION-ONLY ON PURPOSE, so a script on a Mac can walk the state machine
//  without a simulator. It holds no state of its own: the CALLER keeps the count (a per-screen
//  @State, exactly like Android's per-screen rememberSaveable), so the sign-in screen and
//  More each count their own taps and nothing is persisted or sent.
//
//  NOT `onTapGesture(count: 5)`: that one has a system tap interval, i.e. a time window.
//
//  ONE DELIBERATE DIFFERENCE, written down: Kotlin's `require(current in 0 until 5)` throws
//  when the caller hands it an out-of-range count. A phone in a worker's hand must not trap on a
//  gesture counter, so an out-of-range count here simply starts a fresh sequence (it counts as
//  zero). The caller only ever passes back what `advance` returned, so this is unreachable
//  today; it is pinned by the check so it stays harmless.
//

import Foundation

enum VersionTapGate {
    /// Five version-line taps reveal the operator door.
    static let requiredTaps = 5

    /// What a tap did: the count to keep, and whether the operator gate opens now.
    struct Result: Equatable {
        let tapCount: Int
        let openOperator: Bool
    }

    /// One tap. `currentTapCount` is what the previous call returned (0 on a fresh screen).
    static func advance(_ currentTapCount: Int) -> Result {
        let current = (0..<requiredTaps).contains(currentTapCount) ? currentTapCount : 0
        let next = current + 1
        if next == requiredTaps {
            return Result(tapCount: 0, openOperator: true)
        }
        return Result(tapCount: next, openOperator: false)
    }
}
