// Runnable check: the five-tap operator door (TASK-365.13 / iOS B5), and the absence of every
// visible operator row. The twin of android/checks/version-tap-gate-check.kt at 60f6886.
//
//   cd NFCTimeSheets && cat NFCTimeSheets/VersionTapGate.swift NFCTimeSheets/WorkerInitials.swift \
//       checks/version-tap-gate-check.swift > /tmp/vtg.swift && swift /tmp/vtg.swift
//   (checks/run.sh does exactly that)
//
// WHAT IT PINS
//   1. THE RULE, run for real: exactly five taps, taps one to four open nothing, the fifth opens and
//      RESETS the counter, the next sequence starts at one, the rule has no clock in it (it is a pure
//      function of the count), and an out-of-range count starts a fresh sequence instead of trapping.
//   2. THE WIRING, read off disk as text (the screens are SwiftUI; a Mac script cannot instantiate
//      them): no "Write or test tags" row on the signed-out screen or in More, the version line is a
//      VersionGateRow on BOTH screens with its own counter, it calls VersionTapGate.advance exactly
//      once, OperatorHomeScreen is built only behind the fifth tap, and it hides the worker's tab bar.
//   3. THE IDENTITY CARD'S INITIALS (the other pure piece of B5), because it ships in the same screen.
//
// RED CASES reproduced before this was trusted: REQUIRED taps changed to 4; the reset dropped from
// the fifth tap; a time window (`Date`) added to the row; `NavigationLink("Write or test tags")` put
// back on either screen; one of the two VersionGateRow call sites removed; `onTapGesture(count: 5)`
// used instead of the gate; the tab bar left visible under the operator screen.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}
func source(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: \(path) is missing\n".utf8))
        failed = true
        return ""
    }
    return text
}
/// Source without whole-line comments, so a rule written down in prose can never satisfy or trip a pin.
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
func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

// ---------------------------------------------------------------------------------
// 1. THE RULE
// ---------------------------------------------------------------------------------

check(VersionTapGate.requiredTaps == 5, "the gate needs exactly five taps (got \(VersionTapGate.requiredTaps))")

var tapCount = 0
for tap in 1...(VersionTapGate.requiredTaps - 1) {
    let result = VersionTapGate.advance(tapCount)
    check(!result.openOperator, "tap \(tap) opened the operator gate early")
    check(result.tapCount == tap, "tap \(tap) counted \(result.tapCount)")
    tapCount = result.tapCount
}
let fifth = VersionTapGate.advance(tapCount)
check(fifth.openOperator, "the fifth tap did not open the operator gate")
check(fifth.tapCount == 0, "the fifth tap did not reset the counter (reset ONLY on the fifth)")
let nextSequence = VersionTapGate.advance(fifth.tapCount)
check(!nextSequence.openOperator && nextSequence.tapCount == 1, "the next sequence did not start at one")

// Taps one to four never reset anything: the count only ever goes up until the fifth.
var seen: [Int] = []
var c = 0
for _ in 1...4 { c = VersionTapGate.advance(c).tapCount; seen.append(c) }
check(seen == [1, 2, 3, 4], "taps one to four count 1,2,3,4 (got \(seen))")

// A long run: it opens on every fifth tap and on no other.
var opened: [Int] = []
var counter = 0
for tap in 1...100 {
    let r = VersionTapGate.advance(counter)
    counter = r.tapCount
    if r.openOperator { opened.append(tap) }
}
check(opened == Array(stride(from: 5, through: 100, by: 5)), "over 100 taps it opens on every fifth tap and no other (got \(opened.prefix(6)))")

// Out of range: never a trap, never an early open - a fresh sequence.
for bad in [-7, -1, 5, 6, 99] {
    let r = VersionTapGate.advance(bad)
    check(!r.openOperator && r.tapCount == 1, "an out-of-range count (\(bad)) starts a fresh sequence at one (got \(r))")
}

// ---------------------------------------------------------------------------------
// 2. THE WIRING
// ---------------------------------------------------------------------------------

let content = code(source("NFCTimeSheets/ContentView.swift"))
let rowFile = code(source("NFCTimeSheets/VersionGateRow.swift"))
let gateFile = code(source("NFCTimeSheets/VersionTapGate.swift"))
let operatorHome = code(source("NFCTimeSheets/OperatorHomeScreen.swift"))
let style = code(source("NFCTimeSheets/WorkerStyle.swift"))

// No visible operator row anywhere in the app, in either language.
let sourceFiles = ((try? FileManager.default.contentsOfDirectory(atPath: "NFCTimeSheets")) ?? [])
    .filter { $0.hasSuffix(".swift") }.sorted()
check(sourceFiles.count > 20, "the source directory was found (\(sourceFiles.count) files)")
for file in sourceFiles {
    let text = code(source("NFCTimeSheets/\(file)"))
    check(!text.contains("Write or test tags"), "\(file) still shows 'Write or test tags': the operator row is gone (the version line is the door)")
    check(!text.contains("Operator? Write or test tags"), "\(file) still prints the signed-out operator sentence")
    check(!text.contains("onTapGesture(count:"), "\(file) counts taps with the system gesture, which has a time interval: use VersionTapGate")
}
check(!content.contains("operatorSection"), "SignInView has no operatorSection any more")
check(!content.contains("NavigationLink(\"Write or test tags\")"), "no NavigationLink to the operator tools in ContentView.swift")

// The catalogue lost both keys with the rows.
if let data = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let strings = root["strings"] as? [String: Any] {
    check(strings["Write or test tags"] == nil, "the catalogue no longer has the 'Write or test tags' row title")
    check(strings["Operator? Write or test tags without signing in as a worker."] == nil, "...nor the signed-out operator sentence")
    check(strings["Hours, locations and payroll are managed by your admin on the web."] == nil,
          "...nor the 'managed by your admin on the web' sentence (Android left it unreferenced too)")
    func de(_ k: String) -> String? {
        (((((strings[k] as? [String: Any])?["localizations"] as? [String: Any])?["de"]) as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }
    check(de("Installed: %@ (%@)") == "Installiert: %@ (%@)", "the version line keeps decision-52's wording in German")
} else {
    check(false, "Localizable.xcstrings is readable")
}

// The two screens: each owns a VersionGateRow and its own destination.
let signIn = between(content, "struct SignInView: View {", "struct LogView: View {")
let settings = between(content, "struct SettingsView: View {", "\n}\n")
check(!signIn.isEmpty && !settings.isEmpty, "found SignInView and SettingsView in ContentView.swift")
for (name, body) in [("SignInView", signIn), ("SettingsView", settings)] {
    check(count(body, "VersionGateRow(openOperator: $showOperator)") == 1, "\(name) has exactly one version line, driving its own showOperator")
    check(body.contains("@State private var showOperator = false"), "\(name) keeps its own showOperator state")
    check(count(body, ".navigationDestination(isPresented: $showOperator) { OperatorHomeScreen() }") == 1,
          "\(name) pushes OperatorHomeScreen only from the fifth tap")
    check(count(body, "OperatorHomeScreen()") == 1, "\(name) builds OperatorHomeScreen in exactly one place")
}
check(count(content, "VersionGateRow(") == 2 && count(content, "OperatorHomeScreen()") == 2,
      "ContentView.swift has the version line twice (signed out, More) and builds the operator gate only behind them")
// The worker's own tabs never mention the operator tools.
let tabs = between(content, "TabView(selection: $selection) {", ".id(worker.id)")
check(!tabs.isEmpty && !tabs.contains("OperatorHomeScreen"), "the worker's tabs do not mount the operator tools")
// The signed-out section for the line sits after the code form: it is the LAST thing on the screen.
check(signIn.range(of: "CodeSignInSection(")!.lowerBound < signIn.range(of: "VersionGateRow(")!.lowerBound,
      "the version line comes after the sign-in form (the last element, like Android's)")
// ...and it is last in More too: after Sign out.
if let signOut = settings.range(of: "Button(\"Sign out\")"), let version = settings.range(of: "VersionGateRow(") {
    check(signOut.lowerBound < version.lowerBound, "the version line is the last element of More, after Sign out")
} else {
    check(false, "More has Sign out and the version line")
}

// The row itself: a Button, one call to the rule, no clock, a real target, decision-52's wording.
check(rowFile.contains("struct VersionGateRow: View {") && rowFile.contains("Button {") && rowFile.contains(".buttonStyle(.plain)"),
      "the version line is a Button")
check(count(rowFile, "VersionTapGate.advance(tapCount)") == 1, "the row calls the rule exactly once, with its own count")
check(rowFile.contains("tapCount = result.tapCount") && rowFile.contains("if result.openOperator { openOperator = true }"),
      "the row keeps the count the rule returned and opens only when the rule says so")
check(rowFile.contains("@State private var tapCount = 0"), "the count is the row's own per-screen state, never persisted")
for banned in ["Date", "Timer", "DispatchQueue", "Task.sleep", "UserDefaults", "AppStorage", "withAnimation", "sensoryFeedback"] {
    check(!rowFile.contains(banned) && !gateFile.contains(banned),
          "no '\(banned)' in the version line or the rule: no time window, nothing persisted, nothing shown on taps one to four")
}
check(rowFile.contains("Text(\"Installed: \\(Self.appVersion) (\\(Self.appBuild))\")"), "decision-52's wording, unchanged")
check(rowFile.contains("minHeight: WorkerStyle.quietButtonMinHeight") && style.contains("static let quietButtonMinHeight: CGFloat = 48"),
      "the line is at least 48 pt tall (a real target, not footnote text)")
check(rowFile.contains(".contentShape(Rectangle())") && rowFile.contains(".accessibilityIdentifier(\"version-line\")"),
      "the whole row is the target and it has a stable identifier for the hand-run walks")

// The operator screen replaces the scaffold.
check(operatorHome.contains(".toolbarVisibility(.hidden, for: .tabBar)"), "OperatorHomeScreen hides the worker's tab bar")

// ---------------------------------------------------------------------------------
// 3. THE IDENTITY CARD'S INITIALS
// ---------------------------------------------------------------------------------

for (name, initials) in [("Anna Rig", "AR"), ("Bernd Rig", "BR"), ("Hans Peter Müller", "HP"), ("  Maria   Lopez  ", "ML"),
                         ("Cher", "C"), ("", ""), ("   ", ""), ("anna rig", "ar"), ("Éva Ödön", "ÉÖ"), ("Jean-Luc Picard", "JP"),
                         ("李 小龍", "李小")] {
    check(WorkerInitials.of(name) == initials, "initials of '\(name)' are '\(initials)' (got '\(WorkerInitials.of(name))')")
}
let identity = between(code(source("NFCTimeSheets/WorkerHomeViews.swift")), "struct WorkerIdentity: View {", "\n}\n")
check(identity.contains(".accessibilityHidden(true)") && identity.contains(".accessibilityLabel(\"Signed in as \\(name)\")")
      && identity.contains("Text(verbatim: WorkerInitials.of(name))"),
      "the circle is hidden from VoiceOver and the name keeps its spoken label 'Signed in as <name>'")
check(settings.contains("WorkerIdentity(name: worker.name)") && settings.contains("NavigationLink { MyHoursView(worker: worker) } label: { cardRow(\"My hours\") }")
      && settings.contains("NavigationLink(value: SettingsRoute.history) { cardRow(\"History\") }"),
      "the identity card holds the name, My hours and History")
check(!settings.contains("Section(\"Signed in as\")") && !settings.contains("LabeledContent(\"Name\""),
      "the 'Signed in as' header and the 'Name' row are gone: the card is the identity")

if failed { exit(1) }
print("version-tap-gate-check: OK (the rule, the wiring and the initials)")
