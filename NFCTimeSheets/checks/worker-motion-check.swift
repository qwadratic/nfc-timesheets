// Runnable check: the one-shot ring-then-check plays ONLY after a clean server ACK (TASK-365.8, iOS P7,
// decision-83). Ported from Android at 60f6886 (ui/ShiftTimeDisplay.kt `confirmationProgress` and
// `PaymentConfirmation`; docs/ANDROID-WORKER-DESIGN.md "Confirmation motion").
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/ConfirmationMotion.swift checks/worker-motion-check.swift \
//     > /tmp/worker-motion-check.swift && swift /tmp/worker-motion-check.swift
//
// WHAT THE FEATURE IS: a 0.9 s ring that draws, a check that draws inside it, a fade, and then the
// time (clock-in) or the receipt (clock-out) settles. Cosmetic, and the one thing it must never be
// is wrong in the flattering direction: a check shown for a shift the server has NOT accepted is a
// small lie told to somebody whose pay depends on it. The design doc: "Never let animation imply
// server acceptance of a locally queued event."
//
// WHAT THIS CHECK GUARDS, in four parts:
//   1. THE GATE, run for real at fixed instants: plays only when confirmed AND the event is 0...45
//      whole seconds old AND the identity is not the last one consumed. The negative paths are the
//      point: pending, failed and blocked rows (never confirmed), a late ACK, an old shift restored
//      or adopted, a second event of the same receipt, clock skew (an event in the future).
//   2. THE MEMORY, with a scratch UserDefaults suite: the identity is written BEFORE the verdict
//      is returned (so before anything animates), also for the late one that does not play, also
//      under Reduce Motion; clock-in and clock-out are independent; an unconfirmed row consumes
//      nothing; a relaunch (a fresh handle on the same suite) does not replay.
//   3. THE FRAMES: Android's stage arithmetic to the constant (ring, check, exit, content, the
//      0.9 s clock), monotone, and the check and the digits never overlap.
//   4. THE WIRING, read as text: the motion file is Foundation-only and strings-free, the host
//      claims BEFORE it starts and skips only the drawing under Reduce Motion, the ink is never
//      green, the mark is hidden from VoiceOver, there are exactly two call sites with the right
//      inputs, and nothing on the tap path, in the sync pass or in the signals knows it exists.
//
// WHAT THIS CANNOT PIN: that the ring looks right, that it is smooth at 120 Hz, that the minute tick
// of the running screen does not restart it, that Reduce Motion in Settings is what the host reads.
// Those need a worker session on a device or simulator (TASK-365.22 is the rig that signs one in).
//
// RED CASES, reproduced against mutated copies of the real files before this was trusted: see the
// commit that added it.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

func source(_ name: String) -> String {
    guard let text = try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: cannot read NFCTimeSheets/\(name)\n".utf8))
        exit(1)
    }
    return text
}
/// Code only: comments and doc comments carry the rationale and quote the very things this check bans.
func code(_ s: String) -> String {
    s.components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}
func between(_ s: String, _ from: String, _ to: String) -> String {
    let after = s.components(separatedBy: from)
    guard after.count > 1 else { return "" }
    return after[1].components(separatedBy: to)[0]
}
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}
func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
/// Date arithmetic at today's epoch has ~1e-7 s of floating-point slack, so 1e-6 is the honest tolerance.
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

let t0 = Date(timeIntervalSince1970: 1_800_000_000)       // fixed, so nothing depends on "now"
func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

// ---------------------------------------------------------------------------------
// 1. THE GATE
// ---------------------------------------------------------------------------------

let A = "loc-1:1800000000000"
func decide(age: Double, confirmed: Bool = true, last: String? = nil, identity: String = A) -> ConfirmationMotion.Decision {
    ConfirmationMotion.decide(identity: identity, confirmed: confirmed, eventTime: t0, now: at(age), lastConsumed: last)
}
func plays(age: Double, confirmed: Bool = true, last: String? = nil, identity: String = A) -> Bool {
    ConfirmationMotion.shouldPlay(identity: identity, confirmed: confirmed, eventTime: t0, now: at(age), lastConsumed: last)
}

check(ConfirmationMotion.duration == 0.9 && ConfirmationMotion.eligibleAgeSeconds == 45,
      "the motion is 900 ms and the eligibility window is 45 s (docs/ANDROID-WORKER-DESIGN.md)")

// The yes cases: a clean ACK, an event 0...45 whole seconds old, a new identity.
for age in [0.0, 0.4, 1, 20, 44, 45, 45.999] {
    check(decide(age: age) == .play && plays(age: age), "a clean ACK of an event \(age) s old PLAYS")
}
// The window is Android's `age in 0..45` on a FLOORED whole number of seconds: 46 is out.
for age in [46.0, 46.5, 60, 600, 86_400] {
    check(decide(age: age) == .consume && !plays(age: age),
          "a LATE ACK (the event is \(age) s old) is consumed and never plays - 'late delivery is still confirmed in text but does not celebrate an old event'")
}
// CLOCK SKEW: an event that is in the future by any amount is never celebrated (Java: -0.3 s is -1).
for age in [-0.001, -0.3, -1, -3, -3600] {
    check(decide(age: age) == .consume && !plays(age: age),
          "an event \(-age) s in the FUTURE (a phone clock behind the one that wrote it) never plays")
}
// NEVER FOR PENDING, FAILED OR BLOCKED: they are not confirmed, whatever the age, and they consume nothing.
for age in [0.0, 5, 44, 45, 46, 600] {
    check(decide(age: age, confirmed: false) == .nothing && !plays(age: age, confirmed: false),
          "a pending / failed / blocked row (not confirmed) NEVER plays and consumes nothing (age \(age) s)")
}
// ONCE PER IDENTITY.
for age in [0.0, 10, 45, 46, 600] {
    check(decide(age: age, last: A) == .nothing && !plays(age: age, last: A),
          "an identity that was already consumed never plays again (age \(age) s)")
}
check(plays(age: 5, last: "loc-1:1799999999000"), "a DIFFERENT identity consumed last (the previous shift) does not block this one")
check(plays(age: 5, last: nil), "nothing consumed yet plays")
// A second event of the same receipt: same client_uuid, a later finish time (a reopened shift finished again).
let first = ConfirmationMotion.identity(clockOutOf: "c0ffee", endedAt: at(0))
let again = ConfirmationMotion.identity(clockOutOf: "c0ffee", endedAt: at(7200))
check(first != again, "the same row finished again is a different identity")
check(ConfirmationMotion.shouldPlay(identity: again, confirmed: true, eventTime: at(7200), now: at(7203), lastConsumed: first),
      "...and plays: only the identity that was consumed is remembered")
check(!ConfirmationMotion.shouldPlay(identity: first, confirmed: true, eventTime: at(0), now: at(3), lastConsumed: first),
      "...while the first finish never replays")
// A restored / adopted OLD shift: confirmed from its first frame, but the event is hours old.
check(decide(age: 4 * 3600) == .consume, "an old shift adopted from the server updates without an entrance animation")

// IDENTITIES. Millisecond resolution, the kind in the prefix of nothing (the kinds have their own keys).
check(ConfirmationMotion.identity(clockInAt: "L", startedAt: at(1.5)) == "L:1800000001500"
      && ConfirmationMotion.identity(clockInAt: "L", startedAt: at(0)) == "L:1800000000000",
      "a clock-in identity is 'locationId:startMillis'")
check(ConfirmationMotion.identity(clockInAt: "L", startedAt: at(1)) != ConfirmationMotion.identity(clockInAt: "L", startedAt: at(2)),
      "two starts at one building are two identities")
check(ConfirmationMotion.identity(clockInAt: "L", startedAt: at(1)) != ConfirmationMotion.identity(clockInAt: "M", startedAt: at(1)),
      "two buildings at one instant are two identities")
check(ConfirmationMotion.identity(clockOutOf: "U", endedAt: at(3)) == "U:\(ConfirmationMotion.millis(at(3)))",
      "a clock-out identity is 'clientUuid:endMillis'")

// ---------------------------------------------------------------------------------
// 2. THE MEMORY (a scratch UserDefaults suite)
// ---------------------------------------------------------------------------------

let suite = "worker-motion-check.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!

check(ConfirmationMotion.Kind.allCases.count == 2
      && Set(ConfirmationMotion.Kind.allCases.map(\.defaultsKey)).count == 2
      && ConfirmationMotion.Kind.clockIn.rawValue == "clock-in" && ConfirmationMotion.Kind.clockOut.rawValue == "clock-out",
      "two kinds, two keys (Android's 'clock-in' / 'clock-out')")
check(ConfirmationMotion.lastConsumed(.clockIn, in: defaults) == nil && ConfirmationMotion.lastConsumed(.clockOut, in: defaults) == nil,
      "a fresh suite has consumed nothing")

// An unconfirmed row consumes NOTHING, however many times it is looked at.
for age in [1.0, 20, 100] {
    let d = ConfirmationMotion.claim(.clockIn, identity: A, confirmed: false, eventTime: t0, now: at(age), in: defaults)
    check(d == .nothing && ConfirmationMotion.lastConsumed(.clockIn, in: defaults) == nil,
          "a pending row's claim is .nothing and writes nothing (age \(age) s)")
}
// ...and the flip to confirmed (the ACK landing, 12 s after the tap) is the one that plays.
do {
    let d = ConfirmationMotion.claim(.clockIn, identity: A, confirmed: true, eventTime: t0, now: at(12), in: defaults)
    check(d == .play, "the ACK landing 12 s after the tap plays")
    // THE IDENTITY IS ALREADY IN THE PREFERENCE WHEN THE VERDICT COMES BACK - read through a fresh handle.
    let reread = UserDefaults(suiteName: suite)!
    check(ConfirmationMotion.lastConsumed(.clockIn, in: reread) == A,
          "the identity was written BEFORE the verdict was returned: nothing can animate before it is consumed")
    check(ConfirmationMotion.claim(.clockIn, identity: A, confirmed: true, eventTime: t0, now: at(13), in: defaults) == .nothing,
          "a second look (tab return, resume, relaunch) at the same identity is .nothing - no replay")
}
// KINDS ARE INDEPENDENT: the same string consumed as a clock-in is still new as a clock-out.
check(ConfirmationMotion.lastConsumed(.clockOut, in: defaults) == nil, "consuming a clock-in consumed no clock-out")
check(ConfirmationMotion.claim(.clockOut, identity: A, confirmed: true, eventTime: t0, now: at(5), in: defaults) == .play,
      "the clock-out of the same string still plays: the kinds are two memories")
check(ConfirmationMotion.claim(.clockOut, identity: "u:2", confirmed: true, eventTime: t0, now: at(5), in: defaults) == .play
      && ConfirmationMotion.lastConsumed(.clockIn, in: defaults) == A,
      "a new clock-out consumes only the clock-out memory")
// A LATE ACK is consumed (never celebrated later) and never plays.
do {
    let late = "loc-2:1800000100000"
    let d = ConfirmationMotion.claim(.clockIn, identity: late, confirmed: true, eventTime: t0, now: at(90), in: defaults)
    check(d == .consume && ConfirmationMotion.lastConsumed(.clockIn, in: defaults) == late,
          "a late ACK is consumed without playing")
    check(ConfirmationMotion.claim(.clockIn, identity: late, confirmed: true, eventTime: t0, now: at(91), in: defaults) == .nothing,
          "...and is never celebrated afterwards either")
}
// REDUCE MOTION (Android: an animator duration scale of 0): the identity is consumed all the same, only
// the drawing is skipped - so switching the setting off later cannot replay yesterday's check.
do {
    let identity = "loc-3:1800000200000"
    let verdict = ConfirmationMotion.claim(.clockIn, identity: identity, confirmed: true, eventTime: t0, now: at(3), in: defaults)
    check(verdict == .play, "the gate itself does not know about Reduce Motion")
    check(!ConfirmationMotion.animates(verdict, reduceMotion: true), "Reduce Motion: no animation")
    check(ConfirmationMotion.animates(verdict, reduceMotion: false), "...and without it the same verdict animates")
    check(ConfirmationMotion.lastConsumed(.clockIn, in: defaults) == identity, "Reduce Motion: the identity is consumed anyway")
    check(ConfirmationMotion.claim(.clockIn, identity: identity, confirmed: true, eventTime: t0, now: at(4), in: defaults) == .nothing,
          "...so turning Reduce Motion off afterwards does not replay it")
    check(!ConfirmationMotion.animates(.consume, reduceMotion: false) && !ConfirmationMotion.animates(.nothing, reduceMotion: false),
          "only a .play verdict ever animates")
}
// A SECOND event of one receipt, through the memory.
do {
    let one = ConfirmationMotion.identity(clockOutOf: "r1", endedAt: at(10))
    let two = ConfirmationMotion.identity(clockOutOf: "r1", endedAt: at(7300))
    check(ConfirmationMotion.claim(.clockOut, identity: one, confirmed: true, eventTime: at(10), now: at(12), in: defaults) == .play, "the first finish plays")
    check(ConfirmationMotion.claim(.clockOut, identity: two, confirmed: true, eventTime: at(7300), now: at(7302), in: defaults) == .play,
          "the second finish of the same row plays too")
    check(ConfirmationMotion.claim(.clockOut, identity: two, confirmed: true, eventTime: at(7300), now: at(7303), in: defaults) == .nothing,
          "...once")
}

// ---------------------------------------------------------------------------------
// 3. THE FRAMES
// ---------------------------------------------------------------------------------

let s0 = ConfirmationMotion.stage(progress: 0)
check(close(s0.ring, 0) && close(s0.check, 0) && close(s0.exit, 0) && close(s0.contentOpacity, 0)
      && close(s0.contentLift, 12) && close(s0.markOpacity, 1) && close(s0.markScale, 0.92) && close(s0.markLift, 0)
      && !s0.isSettled,
      "frame 0: nothing drawn, the content held back 12 pt low, the pair at 0.92 scale")
check(close(ConfirmationMotion.stage(progress: 0.24).ring, 0.5), "ring = p / 0.48 (half drawn at 0.24)")
check(close(ConfirmationMotion.stage(progress: 0.48).ring, 1) && close(ConfirmationMotion.stage(progress: 0.48).markScale, 1.0),
      "the ring is complete at 0.48 and the pair is at full scale (0.92 + 0.08)")
check(close(ConfirmationMotion.stage(progress: 0.43).check, 0) && close(ConfirmationMotion.stage(progress: 0.53).check, 0.5)
      && close(ConfirmationMotion.stage(progress: 0.63).check, 1),
      "check = (p - 0.43) / 0.2: starts at 0.43, half at 0.53, complete at 0.63")
check(close(ConfirmationMotion.stage(progress: 0.67).exit, 0) && close(ConfirmationMotion.stage(progress: 0.67).markOpacity, 1),
      "the exit has not begun at 0.67")
let mid = ConfirmationMotion.stage(progress: 0.735)
check(close(mid.exit, 0.5) && close(mid.markOpacity, 0.5) && close(mid.markLift, -10) && close(mid.markScale, 1.0 - 0.075),
      "halfway through the exit: half opacity, 10 pt up, scale 1 - 0.075")
let gone = ConfirmationMotion.stage(progress: 0.80)
check(close(gone.exit, 1) && close(gone.markOpacity, 0) && close(gone.markLift, -20) && close(gone.contentOpacity, 0),
      "at 0.80 the pair is gone and the content has not started")
let half = ConfirmationMotion.stage(progress: 0.90)
check(close(half.contentOpacity, 0.5) && close(half.contentLift, 6), "content = (p - 0.80) / 0.20 and rises from 12 pt to 0")
let done = ConfirmationMotion.stage(progress: 1)
check(close(done.contentOpacity, 1) && close(done.contentLift, 0) && close(done.markOpacity, 0) && done.isSettled,
      "at 1.0 the content is fully there, in place, and the motion is settled")
check(ConfirmationMotion.stage(progress: 7) == done && ConfirmationMotion.stage(progress: -3) == s0
      && ConfirmationMotion.stage(progress: .nan) == s0 && ConfirmationMotion.stage(progress: .infinity) == s0,
      "out-of-range progress is clamped; a non-finite one reads as the start")
check(close(ConfirmationMotion.stage(progress: 0).ringStartDegrees, -90) && close(ConfirmationMotion.stage(progress: 0.48).ringStartDegrees, -65)
      && close(ConfirmationMotion.stage(progress: 0.48).ringSweepDegrees, 335) && close(ConfirmationMotion.stage(progress: 0.24).ringSweepDegrees, 167.5),
      "the arc starts at 12 o'clock plus 25 deg of progress and sweeps 335 deg - never a closed circle")

// The clock: linear, 0.9 s, never negative.
check(close(ConfirmationMotion.progress(since: t0, now: at(0.45)), 0.5) && close(ConfirmationMotion.progress(since: t0, now: at(0.9)), 1)
      && close(ConfirmationMotion.progress(since: t0, now: at(5)), 1) && close(ConfirmationMotion.progress(since: t0, now: at(-2)), 0),
      "progress is linear over 0.9 s and clamps at both ends (a clock that went backwards reads 0)")
// The design doc's table, in milliseconds: 0-430 ring, 390-570 check, 600-720 fade, 720-900 settle.
func atMs(_ ms: Double) -> ConfirmationMotion.Stage { ConfirmationMotion.stage(progress: ConfirmationMotion.progress(since: t0, now: at(ms / 1000))) }
check(close(atMs(432).ring, 1) && atMs(430).ring > 0.99, "the ring finishes at ~430 ms")
check(close(atMs(387).check, 0) && atMs(390).check > 0 && close(atMs(567).check, 1), "the check draws from ~390 ms to ~570 ms")
check(close(atMs(603).exit, 0) && close(atMs(720).exit, 1), "the pair fades upward from ~600 ms to 720 ms")
check(close(atMs(720).contentOpacity, 0) && close(atMs(900).contentOpacity, 1), "the time / receipt settles from 720 ms to 900 ms")

// Monotone, and the check and the digits never overlap ("Check and digits do not overlap").
var previous = ConfirmationMotion.stage(progress: 0)
var overlap = false, monotone = true
var p = 0.0
while p <= 1.0 + 1e-12 {
    let s = ConfirmationMotion.stage(progress: p)
    if s.ring < previous.ring || s.check < previous.check || s.exit < previous.exit
        || s.contentOpacity < previous.contentOpacity || s.markOpacity > previous.markOpacity { monotone = false }
    if s.contentOpacity > 0 && s.markOpacity > 0 { overlap = true }
    previous = s
    p += 0.0025
}
check(monotone, "ring, check, exit and content only go forward; the pair's opacity only goes down")
check(!overlap, "the time/receipt is never visible while the ring or the check is (they hand over, they do not overlap)")

// ---------------------------------------------------------------------------------
// 4. THE WIRING, read as text
// ---------------------------------------------------------------------------------

let motion = code(source("ConfirmationMotion.swift"))
let mark = code(source("ConfirmationMark.swift"))
let receiptView = code(source("ShiftReceiptView.swift"))
let screen = code(source("ShiftScreen.swift"))
let content = code(source("ContentView.swift"))

// FOUNDATION-ONLY and strings-free.
check(motion.contains("import Foundation") && !motion.contains("import SwiftUI") && !motion.contains("import UIKit") && !motion.contains("import SwiftData"),
      "ConfirmationMotion.swift is Foundation-only (the check runs it on a Mac with no Xcode)")
check(!motion.contains("ModelContext") && !motion.contains("FetchDescriptor") && !motion.contains("@Query") && !motion.contains("syncPending")
      && !motion.contains("handleTap") && !motion.contains("ShiftAPI") && !motion.contains("TapInbox"),
      "the gate reads no shift and reaches no tap, sync or API: it is values in, a verdict out")
for (name, text) in [("ConfirmationMotion.swift", motion), ("ConfirmationMark.swift", mark)] {
    check(!text.contains("String(localized:") && !text.contains("Text(\"") && !text.contains("LocalizedStringKey") && !text.contains("Label("),
          "\(name) carries no user-visible string (the motion has no words: nothing to translate)")
}

// THE HOST: claims first, animates only when told to, and keeps its clock in a child.
let begin = between(mark, "private func begin() {", "\n    }")
check(inOrder(begin, ["startedAt = nil", "guard confirmed else { return }", "ConfirmationMotion.claim(kind, identity: identity, confirmed: confirmed, eventTime: eventTime)",
                      "guard ConfirmationMotion.animates(decision, reduceMotion: reduceMotion) else { return }", "startedAt = .now"]),
      "begin(): reset, bail when not confirmed, CLAIM the identity, bail when the verdict or Reduce Motion says no, and only then start the clock")
check(count(mark, "startedAt = .now") == 1, "the animation clock is started in exactly one place")
check(mark.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"), "the host reads Reduce Motion from the environment")
check(mark.contains(".onChange(of: Trigger(identity: identity, confirmed: confirmed), initial: true) { _, _ in")
      && mark.contains("private struct Trigger: Equatable"),
      "the trigger is (identity, confirmed) with initial: true - Android's LaunchedEffect(identity, confirmed)")
check(mark.contains("@State private var startedAt: Date?") && !screen.contains("@State private var startedAt"),
      "the animation clock lives in the modifier (a child), not in ShiftScreen whose body is rebuilt once a minute")
check(mark.contains("TimelineView(.animation(paused: startedAt == nil))"),
      "settled is a PAUSED timeline: one render, no frames")
check(mark.contains("ConfirmationMark(stage: stage, ink: ink)") && mark.contains(".accessibilityHidden(true)"),
      "the mark is decoration: hidden from VoiceOver, the time and its label exist throughout")
// NEVER GREEN, no surface of its own, no business reach.
for banned in [".green", "Color.green", "Color(", "UIColor", ".background(", ".cornerRadius", "RoundedRectangle", ".shadow(", ".listRow"] {
    check(!mark.contains(banned), "ConfirmationMark.swift has no green and no surface (found '\(banned)'): decision-60, and the reskin restyles the container")
}
for banned in ["ModelContext", "@Query", "syncPending", "handleTap", "TapInbox", "ShiftSignalCenter", "ShiftAPI", "ShiftFlowAPI", "WorkerScope", "deviceWide", "Shift("] {
    check(!mark.contains(banned), "ConfirmationMark.swift is presentation only: it cannot reach '\(banned)'")
}

// THE TWO CALL SITES, with the right inputs - and no third.
let clockBody = between(screen, "private func clock(presentation: ShiftPresentation, now: Date) -> some View {", "\n    private func instruction(tint: Color) -> some View {")
check(count(clockBody, ".confirmationMotion(") == 1
      && clockBody.contains("kind: .clockIn,")
      && clockBody.contains("identity: ConfirmationMotion.identity(clockInAt: running.locationId, startedAt: running.startTime),")
      && clockBody.contains("confirmed: ShiftSignal.isConfirmed(running, now: now, hasSyncError: syncError?.isEmpty == false),")
      && clockBody.contains("eventTime: running.startTime,")
      && clockBody.contains("ink: .primary)"),
      "the clock card plays for THIS start: identity locationId:startTime, confirmed = ShiftSignal.isConfirmed, the start as the event, ink .primary")
check(inOrder(clockBody, ["return VStack(spacing: 10) {", ".confirmationMotion(", ".frame(maxWidth: .infinity)", ".accessibilityElement(children: .ignore)"]),
      "the motion sits on the content INSIDE the card; the card is still one accessibility element")
let receiptBody = receiptView
check(count(receiptBody, ".confirmationMotion(") == 1
      && receiptBody.contains("kind: .clockOut,")
      && receiptBody.contains("identity: ConfirmationMotion.identity(clockOutOf: shift.clientUuidString, endedAt: end),")
      && receiptBody.contains("confirmed: ShiftReceipt.isConfirmed(row: row, syncError: shift.syncError, needsResolution: needsResolution),")
      && receiptBody.contains("eventTime: end,")
      && receiptBody.contains("ink: .primary)"),
      "the receipt plays for THIS finish: identity clientUuid:endTime, confirmed = ShiftReceipt.isConfirmed read off the row, the finish as the event")
check(inOrder(receiptBody, [".confirmationMotion(", "Button(action: onContinue) {"]),
      "the motion wraps the text block, not the Continue button")
let users = (try? FileManager.default.contentsOfDirectory(atPath: "NFCTimeSheets"))?
    .filter { $0.hasSuffix(".swift") && $0 != "ConfirmationMark.swift" && $0 != "ConfirmationMotion.swift" }
    .filter { code(source($0)).contains("confirmationMotion(") || code(source($0)).contains("ConfirmationMotion.claim") }
    .sorted() ?? []
check(users == ["ShiftReceiptView.swift", "ShiftScreen.swift"], "exactly the clock card and the receipt play it (found \(users))")

// NOTHING ON THE TAP PATH, IN THE SYNC PASS OR IN THE SIGNALS KNOWS IT EXISTS.
for (name, from, to) in [
    ("refresh()", "private func refresh() async {", "\n    }"),
    ("handleTap", "private func handleTap(", "\n    private func outcome("),
    ("startManual", "private func startManual() {", "private func manualStop() {"),
    ("manualStop", "private func manualStop() {", "\n    }"),
    ("finishManualStop", "private func finishManualStop() {", "\n    #if DEBUG"),
    ("prepareCompletion", "private func prepareCompletion(", "\n    }"),
    ("scan", "private func scan() {", "\n    }"),
    ("currentRunning", "private func currentRunning() -> RunningShift? {", "\n    }"),
    ("armIfStillCurrent", "private func armIfStillCurrent() {", "\n    }"),
    ("asRunning", "private func asRunning(_ shift: Shift) -> RunningShift {", "\n    }"),
] {
    let body = between(content, from, to)
    check(!body.isEmpty, "found \(name) in ContentView.swift")
    check(!body.contains("ConfirmationMotion") && !body.contains("confirmationMotion") && !body.contains("ShiftReceipt")
          && !body.contains("receiptMemory") && !body.contains("receiptShift") && !body.contains("recentRows"),
          "\(name) never reads the motion or the receipt (presentation only: it can never gate, delay or alter a tap)")
}
for name in ["Sync.swift", "ShiftSignal.swift", "ShiftSignalCenter.swift", "TapInbox.swift", "TapScanner.swift", "Auth.swift", "ManualStart.swift",
             "Zones.swift", "RosterZones.swift", "WorkerScope.swift", "AppUpdate.swift", "Telemetry.swift", "PendingNotice.swift",
             "PendingWork.swift", "LiveActivityController.swift", "MaterialStore.swift", "OperatorSession.swift", "OperatorAPI.swift"] {
    let text = code(source(name))
    check(!text.contains("ConfirmationMotion") && !text.contains("confirmationMotion") && !text.contains("ShiftReceipt"),
          "\(name) does not know the motion or the receipt exists (it is never an input to a tap, a sync pass, a signal or a session)")
}
// The only consumers of the preference are the gate itself.
check(count(motion, "UserDefaults") >= 1
      && ((try? FileManager.default.contentsOfDirectory(atPath: "NFCTimeSheets"))?
          .filter { $0.hasSuffix(".swift") && $0 != "ConfirmationMotion.swift" }
          .filter { code(source($0)).contains("worker-motion") } ?? []).isEmpty,
      "the 'worker-motion' preference is read and written in ConfirmationMotion.swift and nowhere else")
check(!between(code(source("NFCTimeSheetsApp.swift")), "private func invalidateCachesIfUpdated", "\n}").contains("worker-motion"),
      "decision-62's cache invalidation does not touch it: it is presentation memory, not a cache of the server")

// The scratch suite never outlives the run (also when it failed: exit below skips any defer). The domain is
// removed, and so is the empty plist the preferences daemon leaves behind - this check owns that file.
defaults.removePersistentDomain(forName: suite)
try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Preferences/\(suite).plist")

if failed { exit(1) }
print("worker-motion-check: OK")
