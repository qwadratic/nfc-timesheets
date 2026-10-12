//
//  ConfirmationMotion.swift
//  NFCTimeSheets
//
//  WHEN THE RING-THEN-CHECK MAY PLAY, and what each of its frames is (decision-83, TASK-365.8 /
//  iOS P7). Ported from Android's ui/ShiftTimeDisplay.kt at 60f6886 - `confirmationProgress` for
//  the gate and `PaymentConfirmation` for the arithmetic - and from docs/ANDROID-WORKER-DESIGN.md
//  "Confirmation motion". The views that DRAW it are ConfirmationMark.swift.
//
//  FOUNDATION-ONLY ON PURPOSE (like ShiftSignal / PendingWork / WorkerScope):
//  checks/worker-motion-check.swift cats this file in and runs it on a Mac with no Xcode, with fixed
//  instants and a scratch UserDefaults suite, because the failure it prevents is silent: a check
//  that plays for a shift the server has NOT accepted is a small lie told to somebody whose pay
//  depends on it.
//
//  THE GATE, one function (`decide`, and `shouldPlay` for the yes/no):
//
//      plays  <=>  confirmed  AND  whole seconds since the event in 0...45  AND  identity not consumed
//
//    - CONFIRMED is a CLEAN ACK and nothing less: for a clock-in, `ShiftSignal.isConfirmed` (the
//      open was acknowledged, no error is recorded, not past 8 hours); for a clock-out,
//      `ShiftReceipt.isConfirmed` (delivered, no error, no finish time left to resolve). A pending,
//      failed or blocked row is not confirmed, so it neither plays nor consumes anything.
//    - THE WINDOW is Android's `Duration.between(event, now).seconds in 0..45`: whole seconds,
//      floored, so a finish time in the future (a phone clock behind the server's) is never
//      celebrated and an old event that merely got its ACK late is confirmed in WORDS and never
//      celebrated ("late delivery is still confirmed in text but does not celebrate an old event").
//      That is also what excludes a shift adopted from the server or restored after a reinstall.
//    - ONCE PER IDENTITY, kept per KIND in UserDefaults like Android's "worker-motion"
//      SharedPreferences: clock-in and clock-out are independent. The identity is written BEFORE
//      anything animates (`claim`), for every confirmed identity that has not been consumed - the
//      late one that does not play included - and a Reduce Motion phone consumes it too, so turning
//      the setting off later cannot replay yesterday's check.
//
//  PRESENTATION ONLY. Nothing here reads a shift, writes one, or is read by a tap, a sync pass, a
//  signal or navigation; the preference is not a cache and is not covered by decision-62. Clearing
//  it replays at most one check, and only for a clean ACK of an event under 45 s old.
//
//  THE FRAMES (`stage`) are Android's, on a LINEAR 0.9 s clock, to the constant:
//
//      ring     0 ... 0.48   (0 ... 432 ms)   arc from 12 o'clock + 25 deg, sweeping 335 deg
//      check    0.43 ... 0.63 (387 ... 567 ms)
//      exit     0.67 ... 0.80 (603 ... 720 ms)  ring and check fade upward and shrink
//      content  0.80 ... 1.00 (720 ... 900 ms)  the time / the receipt fades up into place
//

import Foundation

enum ConfirmationMotion {

    // MARK: Constants

    /// The whole motion, linear.
    static let duration: TimeInterval = 0.9

    /// Android: `age in 0..45`.
    static let eligibleAgeSeconds = 45

    // MARK: Kinds and identities

    /// Two independent memories, one per kind of event (Android's preference keys "clock-in" /
    /// "clock-out").
    enum Kind: String, CaseIterable, Equatable {
        case clockIn = "clock-in"
        case clockOut = "clock-out"

        /// The UserDefaults key. A presentation preference, never read by anything that decides.
        var defaultsKey: String { "worker-motion.\(rawValue)" }
    }

    /// 'locationId:startMillis' - Android's "${running.locationId}:${running.startTime}". The start
    /// time is the phone's own and is never overwritten by the server's copy, so it is stable.
    static func identity(clockInAt locationId: String, startedAt: Date) -> String {
        "\(locationId):\(millis(startedAt))"
    }

    /// 'clientUuid:endMillis' - Android's "${shift.clientUuid}:$end". Asked only of a row that is
    /// already confirmed, i.e. after the server's copy of the finish time has been applied, so the
    /// millisecond truncation of that copy cannot change it afterwards.
    static func identity(clockOutOf clientUuid: String, endedAt: Date) -> String {
        "\(clientUuid):\(millis(endedAt))"
    }

    static func millis(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        return value.isFinite ? Int64(value.rounded()) : 0
    }

    // MARK: The gate

    enum Decision: Equatable {
        /// Not confirmed, or this identity was already consumed: nothing happens, nothing is recorded.
        case nothing
        /// Confirmed and new, but the event is too old (or in the future): record it, never play it.
        case consume
        /// Confirmed, new, and the event is at most 45 s old: record it, THEN play.
        case play
    }

    /// Whole seconds from the event to `now`, floored (Java's `Duration.seconds`: -0.3 s is -1).
    static func ageSeconds(of eventTime: Date, now: Date) -> Int {
        let seconds = now.timeIntervalSince(eventTime)
        guard seconds.isFinite else { return Int.min }
        return Int(max(min(seconds.rounded(.down), 1e9), -1e9))
    }

    static func decide(identity: String, confirmed: Bool, eventTime: Date, now: Date,
                       lastConsumed: String?) -> Decision {
        guard confirmed else { return .nothing }
        guard lastConsumed != identity else { return .nothing }
        return (0...eligibleAgeSeconds).contains(ageSeconds(of: eventTime, now: now)) ? .play : .consume
    }

    /// Android's `shouldPlay`, as the plan names it.
    static func shouldPlay(identity: String, confirmed: Bool, eventTime: Date, now: Date,
                           lastConsumed: String?) -> Bool {
        decide(identity: identity, confirmed: confirmed, eventTime: eventTime, now: now,
               lastConsumed: lastConsumed) == .play
    }

    // MARK: The memory

    static func lastConsumed(_ kind: Kind, in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: kind.defaultsKey)
    }

    /// THE ONE CALL THE VIEW MAKES. Reads the preference, decides, and WRITES THE IDENTITY BEFORE it
    /// returns - so by the time the caller is told `.play`, the identity is already consumed and no
    /// later launch, tab return or resume can replay it, whatever happens to the animation.
    @discardableResult
    static func claim(_ kind: Kind, identity: String, confirmed: Bool, eventTime: Date,
                      now: Date = .now, in defaults: UserDefaults = .standard) -> Decision {
        let decision = decide(identity: identity, confirmed: confirmed, eventTime: eventTime, now: now,
                              lastConsumed: lastConsumed(kind, in: defaults))
        if decision != .nothing { defaults.set(identity, forKey: kind.defaultsKey) }
        return decision
    }

    /// Reduce Motion (Android: an animator duration scale of 0) shows the STABLE state: the identity
    /// has been claimed above either way, only the drawing is skipped.
    static func animates(_ decision: Decision, reduceMotion: Bool) -> Bool {
        decision == .play && !reduceMotion
    }

    // MARK: The frames

    /// 0 at the start, 1 from `duration` on; a clock that jumped backwards reads 0, never negative.
    static func progress(since start: Date, now: Date) -> Double {
        clamp(now.timeIntervalSince(start) / duration)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Everything a frame needs, as numbers. The views multiply the two lifts by points and
    /// the degrees are what `ConfirmationMark` rotates and trims by.
    struct Stage: Equatable {
        let progress: Double
        /// 0...1 - how much of the ring is drawn.
        let ring: Double
        /// 0...1 - how much of the check is drawn.
        let check: Double
        /// 0...1 - how far through its fade-up the pair is.
        let exit: Double
        /// 0...1 - the time / the receipt. Exactly 1 once the motion is over.
        let contentOpacity: Double
        /// Points the content sits BELOW its place while it fades in (12 pt at the start).
        let contentLift: Double
        let markOpacity: Double
        let markScale: Double
        /// Points the pair has risen (negative = up) while it fades out.
        let markLift: Double

        /// Where the arc starts, clockwise from 3 o'clock: 12 o'clock plus a quarter-turn's share.
        var ringStartDegrees: Double { -90 + 25 * ring }
        /// How far the arc sweeps: 335 degrees when complete (never a closed circle).
        var ringSweepDegrees: Double { 335 * ring }

        var isSettled: Bool { progress >= 1 }
    }

    static func stage(progress raw: Double) -> Stage {
        let p = clamp(raw)
        let ring = clamp(p / 0.48)
        let check = clamp((p - 0.43) / 0.2)
        let exit = clamp((p - 0.67) / 0.13)
        let content = p >= 1 ? 1 : clamp((p - 0.80) / 0.20)
        return Stage(progress: p,
                     ring: ring,
                     check: check,
                     exit: exit,
                     contentOpacity: content,
                     contentLift: (1 - content) * 12,
                     markOpacity: 1 - exit,
                     markScale: 0.92 + 0.08 * min(p / 0.48, 1) - exit * 0.15,
                     markLift: -exit * 20)
    }
}
