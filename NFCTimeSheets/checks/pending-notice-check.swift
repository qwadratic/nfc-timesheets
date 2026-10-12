// Runnable check: "Not confirmed yet" on the running screen (TASK-365.6, iOS P5).
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/ShiftSignal.swift NFCTimeSheets/PendingNotice.swift \
//     checks/pending-notice-check.swift > /tmp/pending-notice-check.swift \
//     && swift /tmp/pending-notice-check.swift
//
// WHAT THE FEATURE IS: a start that exists only on the phone (Shift.openSyncedAt == nil) is SAID so -
// heading "Not confirmed yet", the word "Time recorded on this phone", a spoken label, and ONE line
// under the clock with the row's own delivery problem (or "Saved on this phone") and a Refresh
// button. Ported from Android at 60f6886 (TimeSheetApp.kt, ShiftSignal.kt, ShiftSignals.kt).
// shift-signal-check.swift pins the other half: plan(pending) == plan(not pending), the ladder, the
// re-arm after the push.
//
// WHAT THIS CHECK GUARDS, in four parts:
//   1. THE GRACE. iOS writes the row BEFORE the POST, so every online tap is unacknowledged for one
//      request: the screen waits 2 s before it claims anything, unless the row already carries a
//      sync error or the start is already old. (Android has no grace; this is the one deviation.)
//   2. THE NOTICE DECISION, run for real: when it shows, what it says, red only for a refused row,
//      the line follows the flag and the error and NOT the overdue precedence (Android), an empty
//      error sentence is no error.
//   3. THE WIRING, read as text: the notice is a SEPARATE view placed after the clock card and
//      never inside it (the card is one accessibility element with children ignored), it carries
//      no surface of its own (the Blue Hour reskin restyles the container), the words are three
//      small functions of the presentation, the clock counts for a pending start exactly as for a
//      running one, and NOTHING is hidden or disabled by any of this.
//   4. THE STRINGS: both languages, the exact keys, German = Android's verbatim, and the dead
//      Android sentence (shift_pending_body) is NOT ported.
//
// WHAT THIS CANNOT PIN: that the screen looks right, that the 2 s grace really keeps an online tap
// from flashing the heading, that VoiceOver reads the label and finds Refresh as its own control.
// Those need a worker session on a simulator or phone (TASK-365.22 is the rig that signs one in).

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // fixed, so nothing depends on "now"
func after(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

// ---------------------------------------------------------------------------------
// 1. The grace
// ---------------------------------------------------------------------------------

check(PendingNotice.grace == 2, "the grace is 2 seconds")
check(PendingNotice.staleAfter == 10, "a start older than 10 seconds skips the grace")
check(!PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(0), hasSyncError: false),
      "a start that is brand new waits out the grace (an online tap is unacknowledged for one request)")
check(!PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(9.99), hasSyncError: false),
      "9.99 s old still waits")
check(PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(10), hasSyncError: false),
      "exactly 10 s old does not wait: the app was reopened on a start that nobody has answered")
check(PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(3600), hasSyncError: false),
      "an hour-old unacknowledged start does not wait either")
check(PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(0), hasSyncError: true),
      "a sync error ends the wait at once: the server answered, and the answer was no")
check(!PendingNotice.graceElapsedAtOnce(startedAt: t0, now: after(-30), hasSyncError: false),
      "a phone whose clock jumped backwards does not count a negative age as old")

// ---------------------------------------------------------------------------------
// 2. The notice decision
// ---------------------------------------------------------------------------------

let acknowledged = RunningShift(locationId: "3f2504e0-4f89-11d3-9a0c-0305e82c3301", locationName: "Westbahnhof",
                                startTime: t0)
let unacknowledged = RunningShift(locationId: acknowledged.locationId, locationName: acknowledged.locationName,
                                  startTime: t0, pendingConfirmation: true)
let overdueButUnacknowledged = RunningShift(locationId: acknowledged.locationId, locationName: acknowledged.locationName,
                                            startTime: t0, serverAutoClosed: true, pendingConfirmation: true)
let offline = "No connection - will send when you're back online."
let refused = "This tag hasn't been activated yet. No shift was started. Please contact your administration."

func notice(_ running: RunningShift, grace: Bool, error: String?, blocked: Bool = false) -> PendingNotice.Content? {
    PendingNotice.content(for: running, graceElapsed: grace, syncError: error, syncBlocked: blocked)
}

check(notice(acknowledged, grace: true, error: nil) == nil && notice(acknowledged, grace: false, error: nil) == nil,
      "an acknowledged shift with no error shows no notice")
check(notice(unacknowledged, grace: false, error: nil) == nil,
      "DURING THE GRACE an unacknowledged start with no error shows no notice (no flash at a normal clock-in)")
check(notice(unacknowledged, grace: true, error: nil) == .savedLocally,
      "after the grace an unacknowledged start says it is only saved on this phone")
check(notice(unacknowledged, grace: true, error: offline) == .problem(offline, blocked: false),
      "...and the row's own sentence wins over the generic one (Android: syncError ?: worker_saved_locally)")
check(notice(unacknowledged, grace: false, error: offline) == .problem(offline, blocked: false),
      "a sync error shows at once, grace or no grace")
check(notice(unacknowledged, grace: false, error: refused, blocked: true) == .problem(refused, blocked: true),
      "a REFUSED row (zone_unverified, unknown_location) shows its sentence, flagged blocked: the red icon")
check(notice(acknowledged, grace: true, error: offline) == .problem(offline, blocked: false),
      "Android also shows an ACKNOWLEDGED shift's sync error, with Refresh")
check(notice(unacknowledged, grace: true, error: "") == .savedLocally && notice(acknowledged, grace: true, error: "") == nil,
      "an empty error sentence is no error (never an empty line with a button under it)")
check(notice(unacknowledged, grace: true, error: nil, blocked: true) == .savedLocally,
      "'blocked' without a sentence says nothing red: there is nothing to say")
check(notice(overdueButUnacknowledged, grace: true, error: nil) == .savedLocally,
      "THE LINE FOLLOWS THE FLAG AND THE ERROR, NOT THE OVERDUE PRECEDENCE: an unacknowledged start keeps its notice and Refresh under 'Over 8 hours' (Android)")
check(PendingNotice.content(pending: true, syncError: nil, syncBlocked: false) == .savedLocally
      && PendingNotice.content(pending: false, syncError: nil, syncBlocked: false) == nil
      && PendingNotice.content(pending: false, syncError: offline, syncBlocked: true) == .problem(offline, blocked: true),
      "content(pending:syncError:syncBlocked:) is the whole rule: error first, then the flag")

// ---------------------------------------------------------------------------------
// 3. The wiring, read as text
// ---------------------------------------------------------------------------------

func source(_ name: String) -> String {
    guard let text = try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: cannot read NFCTimeSheets/\(name)\n".utf8)); exit(1)
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
    let parts = s.components(separatedBy: from)
    guard parts.count > 1 else { return "" }
    return parts[1].components(separatedBy: to)[0]
}

let screen = code(source("ShiftScreen.swift"))
let noticeView = code(source("PendingNoticeView.swift"))
let noticeLogic = code(source("PendingNotice.swift"))
let content = code(source("ContentView.swift"))

// The notice is its own view, drawn AFTER the clock card and BEFORE the instruction, never inside the clock.
let stack = between(screen, "VStack(spacing: 24) {", ".frame(maxWidth: .infinity)")
let at = (
    header: stack.range(of: "header(presentation: presentation, tint: tint)"),
    clock: stack.range(of: "clock(presentation: presentation, now: context.date)"),
    notice: stack.range(of: "PendingNoticeView(content: content, onRefresh: onRefresh)"),
    instruction: stack.range(of: "instruction(tint: tint)"),
    scan: stack.range(of: "scanButton"),
    stop: stack.range(of: "stopButton")
)
if let h = at.header, let c = at.clock, let n = at.notice, let i = at.instruction, let sc = at.scan, let st = at.stop {
    check(h.upperBound < c.lowerBound && c.upperBound < n.lowerBound && n.upperBound < i.lowerBound
          && i.upperBound < sc.lowerBound && sc.upperBound < st.lowerBound,
          "running screen order: header, clock, the NOTICE, the tap instruction, Scan, Finish without a tag")
} else { check(false, "the running screen stack has header, clock, PendingNoticeView, instruction, scan and stop") }
let clockBody = between(screen, "private func clock(presentation: ShiftPresentation, now: Date) -> some View {", "\n    private func instruction(tint: Color) -> some View {")
check(!clockBody.isEmpty, "found clock(presentation:now:)")
check(!clockBody.contains("PendingNotice") && !clockBody.contains("Button") && !clockBody.contains("onRefresh"),
      "THE TRAP: the notice and its Refresh are NOT inside clock(): that card is accessibilityElement(children: .ignore) and would swallow them")
check(clockBody.contains(".accessibilityElement(children: .ignore)"),
      "...which is exactly why (the card is still one element; this check fails if that stops being true and the trap is gone)")
check(noticeView.contains("Button(\"Refresh\", action: onRefresh)") && noticeView.contains(".buttonStyle(.bordered)"),
      "Refresh is a bordered Button calling the closure it was given")

// A pending start's clock COUNTS: ONE call, and its only input besides the start is whether the shift is OVERDUE -
// so everything that is not overdue, pending included, draws the ticking digits from the LOCAL start.
// (TASK-365.11: Text(timerInterval:) drew one size; ShiftTimeDigits draws HH:MM large and the seconds small,
// ticking in its own per-second TimelineView, from the same start and clamped at the same 8 h deadline.)
check(clockBody.components(separatedBy: "ShiftTimeDigits(").count - 1 == 1
      && clockBody.contains("ShiftTimeDigits(startTime: running.startTime, overdue: presentation == .overdue)"),
      "everything that is not overdue - pending included - draws the ticking digits from the local start")
check(!clockBody.contains("Text(timerInterval:") && !clockBody.contains("8:00:00+"),
      "...and the old one-size system clock and its literal are gone from the clock block")
check(!clockBody.contains(".pending"), "clock() never branches on .pending: the digits are identical, only the words differ")

// The three words are three small functions of the presentation, strongest first.
let heading = between(screen, "private func headingText(_ presentation: ShiftPresentation) -> Text {", "\n    }")
let word = between(screen, "private func stateWord(_ presentation: ShiftPresentation) -> Text {", "\n    }")
let spoken = between(screen, "private func spokenState(_ presentation: ShiftPresentation, elapsed: (hours: Int, minutes: Int)) -> Text {", "\n    }")
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}
check(inOrder(heading, ["case .overdue: return Text(\"Over 8 hours\")", "case .pending: return Text(\"Not confirmed yet\")",
                        "case .running: return Text(\"Shift in progress\")"]),
      "the heading is 'Over 8 hours' / 'Not confirmed yet' / 'Shift in progress' (Android worker_active_title), overdue > pending > running")
check(inOrder(word, ["case .overdue: return Text(\"This shift passed 8 hours and was closed automatically.",
                     "case .pending: return Text(\"Time recorded on this phone\")", "case .running: return Text(\"Running\")"]),
      "the word under the clock is the overdue sentence / 'Time recorded on this phone' / 'Running'")
check(inOrder(spoken, ["case .overdue:", "passed 8 hours and was closed automatically. Confirm when you finished.",
                       "case .pending:",
                       "Text(\"\\(elapsed.hours) hours and \\(elapsed.minutes) minutes recorded on this phone for \\(running.locationName). Not confirmed by the office yet.\")",
                       "case .running:", "Text(\"Shift running for \\(elapsed.hours) hours \\(elapsed.minutes) minutes at \\(running.locationName)\")"]),
      "the VoiceOver label is the overdue sentence / 'N hours and M minutes recorded on this phone for B. Not confirmed...' / 'Shift running for ...'")
check(between(screen, "private func header(presentation: ShiftPresentation, tint: Color) -> some View {", "Text(running.locationName)").contains("headingText(presentation)")
      && between(screen, "private func header(presentation: ShiftPresentation, tint: Color) -> some View {", "Text(running.locationName)").contains(".accessibilityAddTraits(.isHeader)"),
      "the heading is headingText(presentation) and is still a VoiceOver header")
check(clockBody.contains("stateWord(presentation)") && clockBody.contains(".accessibilityLabel(spokenState(presentation, elapsed: elapsed))"),
      "clock() draws stateWord and reads spokenState for the same presentation")
check(!screen.contains("? Text(") && !screen.contains("Text(overdue ?") && !screen.contains("Text(presentation ==")
      && !screen.contains("overdue ? \"") && !screen.contains("Text(verbatim: \""),
      "no ternary of two string literals (the verbatim initialiser ships English, TASK-298) and no verbatim literal in ShiftScreen")

// The presentation is the ONE function, asked of the tick's date, the grace and the row's error.
check(screen.contains("let presentation = ShiftSignal.presentation(of: running, now: context.date,")
      && screen.contains("graceElapsed: graceOver, hasSyncError: hasError)"),
      "the screen asks ShiftSignal.presentation for its words (overdue > pending > running)")
check(screen.contains("PendingNotice.graceElapsedAtOnce(startedAt: running.startTime, now: .now, hasSyncError: hasError)"),
      "an old start or a row with an error skips the grace (the REAL now, not the once-a-minute tick)")
check(screen.contains("let hasError = syncError?.isEmpty == false"), "an error sentence that is empty is not an error")
let graceTask = between(screen, ".task(id: GraceKey(startTime: running.startTime, pending: running.pendingConfirmation)) {", "\n        }")
check(graceTask.contains("graceElapsed = false") && graceTask.contains("guard running.pendingConfirmation else { return }")
      && graceTask.contains("try? await Task.sleep(for: .seconds(PendingNotice.grace))")
      && graceTask.contains("if !Task.isCancelled { graceElapsed = true }"),
      "the grace task: reset, nothing to wait for if acknowledged, sleep PendingNotice.grace, claim only if not cancelled")
check(screen.contains("PendingNotice.content(for: running, graceElapsed: graceOver,")
      && screen.contains("syncError: syncError, syncBlocked: syncBlocked)"),
      "the notice's content comes from PendingNotice.content with the same grace the heading uses")

// NOTHING IS HIDDEN OR DISABLED. The `if` lines in the running stack are the four that were already
// conditional on something else; no control is gated on the presentation, the flag or the grace.
let ifLines = stack.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("if ") }
check(ifLines.count == 4
      && ifLines[0].hasPrefix("if let content = PendingNotice.content(for: running, graceElapsed: graceOver,")
      && ifLines[1] == "if let notice { noticeCard(notice) }"
      && ifLines[2] == "if unresolvedCount > 0 { resolverCard }"
      && ifLines[3] == "if signals.outOfAppSignalsSilenced { notificationsOffCard }",
      "the running stack has exactly four conditionals - the notice, the move notice, the resolver, notifications-off: Scan, Finish, help and the plan are unconditional (got \(ifLines))")
check(!screen.contains(".disabled(") && !screen.contains(".hidden()") && !screen.contains(".opacity(0)"),
      "ShiftScreen disables and hides nothing")
check(!between(screen, "private var scanButton: some View {", "\n    }").contains("presentation")
      && !between(screen, "private var stopButton: some View {", "\n    }").contains("presentation"),
      "Scan and Finish do not know the presentation")
check(!screen.contains("pendingConfirmation ?") && screen.components(separatedBy: "running.pendingConfirmation").count - 1 == 2,
      "ShiftScreen reads the flag in exactly two places (the grace task's key and its guard) and branches on nothing else")

// The caller passes the OPEN row's own sentence and the same refresh pull-to-refresh runs.
check(content.contains("syncError: openRow?.syncError,\n                                syncBlocked: openRow?.syncBlocked ?? false,\n                                onRefresh: { Task { await refresh() } },\n                                schedule: schedule.state,"),
      "LogView hands ShiftScreen the open row's syncError / syncBlocked and `{ Task { await refresh() } }` (the pull-to-refresh function) before the plan")

// THE NOTICE VIEW: no surface, no colour but a refused row's red, no behaviour of its own.
for banned in [".background(", ".listRow", "RoundedRectangle", "Capsule(", ".clipShape", ".cornerRadius", ".shadow(", "Color(", "Color.",
               ".overlay(", ".border(", "UIColor", ".foregroundColor(", ".fill(", ".stroke(", ".padding("] {
    check(!noticeView.contains(banned),
          "PendingNoticeView.swift has no hard-coded surface (found '\(banned)'): the Blue Hour reskin restyles the container, not this view")
}
let noticeStyles = noticeView.components(separatedBy: ".foregroundStyle(").dropFirst().map { $0.components(separatedBy: ")")[0] }
check(noticeStyles == [".red"], "the notice's only colour is the red icon of a refused row (got \(noticeStyles))")
check(noticeView.contains("if case .problem(_, blocked: true) = content {")
      && inOrder(noticeView, ["if case .problem(_, blocked: true) = content {", "xmark.octagon.fill", ".foregroundStyle(.red)", ".accessibilityHidden(true)"]),
      "the red icon is drawn for a BLOCKED problem only, and is decoration (the sentence beside it says it)")
check(noticeView.contains("Text(verbatim: text)"),
      "the row's sentence is already localised data: drawn verbatim, never looked up again")
check(noticeView.contains("String(localized: \"Saved on this phone · not yet confirmed\")"), "the generic line goes through the catalogue")
check(noticeView.contains("AccessibilityNotification.Announcement(") && noticeView.contains("accessibilitySpeechAnnouncementPriority = .low")
      && noticeView.contains(".onAppear { announce() }") && noticeView.contains(".onChange(of: text) { announce() }"),
      "the line is a POLITE live region: a low-priority announcement when it appears and when its text changes")
for banned in ["ShiftSignalCenter", "ModelContext", "@Environment", "@Query", "Shift(", "ShiftAPI", "ShiftFlowAPI", "URLSession", "apiGet", "apiPost", "handleTap", ".disabled("] {
    check(!noticeView.contains(banned) && !noticeLogic.contains(banned),
          "the notice is display only and adds no endpoint: it cannot reach '\(banned)'")
}
check(!noticeLogic.contains("import SwiftUI") && !noticeLogic.contains("import UIKit") && !noticeLogic.contains("import SwiftData")
      && !noticeLogic.contains("UserDefaults") && !noticeLogic.contains("FileManager"),
      "PendingNotice.swift is Foundation-only and persists nothing")

// The Live Activity is NOT told (no widget extension target exists; that is the owner's step).
let activity = code(source("ShiftActivityAttributes.swift"))
check(activity.contains("public var overdue: Bool") && !activity.lowercased().contains("pending"),
      "ShiftActivityAttributes.ContentState still carries only `overdue`: the pending state is not ported to the Live Activity")
check(!code(source("LiveActivityController.swift")).lowercased().contains("pending"), "LiveActivityController does not know the flag")

// ---------------------------------------------------------------------------------
// 4. The strings: both languages, the exact keys, the German is Android's
// ---------------------------------------------------------------------------------

guard let catalogueData = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
      let catalogueRoot = try? JSONSerialization.jsonObject(with: catalogueData) as? [String: Any],
      let catalogue = catalogueRoot["strings"] as? [String: Any]
else { print("FAIL: Localizable.xcstrings unreadable"); exit(1) }

func german(_ key: String) -> String? {
    (((catalogue[key] as? [String: Any])?["localizations"] as? [String: Any])?["de"] as? [String: Any])
        .flatMap { $0["stringUnit"] as? [String: Any] }.flatMap { $0["value"] as? String }
}
func androidStrings(_ path: String) -> [String: String] {
    guard let xml = try? String(contentsOfFile: path, encoding: .utf8) else {
        check(false, "cannot read \(path) - the German of this feature is read out of it"); return [:]
    }
    var out: [String: String] = [:]
    let entry = try! NSRegularExpression(pattern: #"<string name="([^"]+)"[^>]*>([\s\S]*?)</string>"#)
    for m in entry.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
        out[String(xml[Range(m.range(at: 1), in: xml)!])] = String(xml[Range(m.range(at: 2), in: xml)!])
            .replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
    return out
}
let res = "../android/app/src/main/res"
let androidDe = androidStrings("\(res)/values/strings.xml")          // default resources ARE German
let androidEn = androidStrings("\(res)/values-en/strings.xml")
/// The key the compiler extracts: non-positional, %d -> %lld, %s -> %@.
func iosKey(_ s: String) -> String {
    s.replacingOccurrences(of: #"%\d+\$d"#, with: "%lld", options: .regularExpression)
        .replacingOccurrences(of: #"%\d+\$s"#, with: "%@", options: .regularExpression)
        .replacingOccurrences(of: "%d", with: "%lld").replacingOccurrences(of: "%s", with: "%@")
}
/// The German value: positions kept (German reorders), %d -> %lld, %s -> %@; ONE placeholder loses its position.
func iosValue(_ s: String) -> String {
    var v = s.replacingOccurrences(of: #"%(\d+)\$d"#, with: "%$1\\$lld", options: .regularExpression)
        .replacingOccurrences(of: #"%(\d+)\$s"#, with: "%$1\\$@", options: .regularExpression)
        .replacingOccurrences(of: "%d", with: "%lld").replacingOccurrences(of: "%s", with: "%@")
    if v.components(separatedBy: "%").count - 1 == 1 { v = v.replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression) }
    return v
}

// (Android name, the iOS key, the file that shows it, the text as it is written in that file)
let strings: [(String, String, String, String)] = [
    ("shift_pending_heading", "Not confirmed yet", "ShiftScreen.swift", "Text(\"Not confirmed yet\")"),
    ("shift_pending_label", "Time recorded on this phone", "ShiftScreen.swift", "Text(\"Time recorded on this phone\")"),
    ("a11y_shift_pending", "%lld hours and %lld minutes recorded on this phone for %@. Not confirmed by the office yet.", "ShiftScreen.swift",
     "Text(\"\\(elapsed.hours) hours and \\(elapsed.minutes) minutes recorded on this phone for \\(running.locationName). Not confirmed by the office yet.\")"),
    ("worker_saved_locally", "Saved on this phone · not yet confirmed", "PendingNoticeView.swift", "String(localized: \"Saved on this phone · not yet confirmed\")"),
    ("log_refresh", "Refresh", "PendingNoticeView.swift", "Button(\"Refresh\", action: onRefresh)"),
    ("notify_pending_title", "Not confirmed yet: %@", "ShiftSignalCenter.swift", "String(localized: \"Not confirmed yet: \\(running.locationName)\")"),
    ("notify_pending_body", "Your time is saved on this phone. Open the app and check the message.", "ShiftSignalCenter.swift",
     "String(localized: \"Your time is saved on this phone. Open the app and check the message.\")"),
]
for (name, key, file, written) in strings {
    guard let de = androidDe[name], let en = androidEn[name] else { check(false, "Android has string '\(name)'"); continue }
    check(iosKey(en) == key, "the iOS key for Android's \(name) is Android's English: '\(iosKey(en))' vs '\(key)'")
    check(catalogue[key] != nil && german(key) == iosValue(de),
          "the German for '\(key)' is Android's \(name), verbatim: '\(german(key) ?? "nil")' vs '\(iosValue(de))'")
    check(code(source(file)).contains(written), "\(file) shows '\(key)' through the catalogue, written exactly '\(written)'")
}
check(german("%lld hours and %lld minutes recorded on this phone for %@. Not confirmed by the office yet.")
      == "%1$lld Stunden und %2$lld Minuten für %3$@ auf diesem Telefon erfasst. Noch nicht von der Verwaltung bestätigt.",
      "the spoken label's German is positional (%1$lld %2$lld %3$@): the key is not")
check(!catalogue.keys.contains { $0.contains("has not reached the office yet") || $0.contains("Please check the message below") },
      "Android's shift_pending_body is DEAD there (never read) and is not ported")
check(!(try! String(contentsOfFile: "NFCTimeSheets/Localizable.xcstrings", encoding: .utf8)).contains("Gebäude"),
      "buildings are 'Objekt', never 'Gebäude'")

if failed { exit(1) }
print("pending-notice-check: OK")
