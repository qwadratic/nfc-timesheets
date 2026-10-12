// Runnable check: the "Blue Hour" worker reskin (TASK-365.9 / .10 / .11, iOS B1-B3).
//
//   cd NFCTimeSheets && swift checks/worker-reskin-check.swift
//
// WHY A TEXT CHECK AND NOT A SCREENSHOT: nothing here has a value to compute - it is where things are
// drawn and what they are drawn with. The risk is quiet regression, not a wrong number: a History tab
// that comes back, a primary button that goes back to the system accent, a hand-typed hex in a view,
// a new string with one language. Those are all visible in the source, and the Simulator walks in the
// task notes prove the rendered result once; this keeps it from drifting afterwards.
//
// Reads the Swift sources, the asset catalogue, the string catalogue and ../android/.../ui/Theme.kt
// off disk, so it cannot be cat-ed together with them (same reason as localisation-check.swift).
//
// RED CASES reproduced before this was trusted (see the commits): the History tab put back into the
// ForEach; `.borderedProminent` back on the idle Scan button; `Label("Log"` restored; `selection = .log`
// dropped from the tap arrival; the WorkerInverse colour set edited to another hex; a NavigationStack
// back inside HistoryView; one of the new keys left without its English entry.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

func source(_ name: String) -> String {
    (try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8)) ?? ""
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
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}

let style = code(source("WorkerStyle.swift"))
let content = code(source("ContentView.swift"))
let shiftScreen = code(source("ShiftScreen.swift"))

// ---------------------------------------------------------------------------------
// 1. THE SHARED TOKENS (worker-surface-tokens)
// ---------------------------------------------------------------------------------

check(!style.isEmpty, "WorkerStyle.swift exists: one file for the worker's surfaces, buttons and titles")
check(style.contains("static let cardRadius: CGFloat = 18"), "a card is 18 pt (Android WorkerCard RoundedCornerShape(18.dp))")
check(style.contains("static let buttonRadius: CGFloat = 16") && style.contains("static let buttonMinHeight: CGFloat = 56"),
      "the primary button is 16 pt rounded and at least 56 pt tall (Android RoundedCornerShape(16.dp), heightIn(min = 56.dp))")
check(style.contains("static let quietButtonMinHeight: CGFloat = 48"), "a quiet text button is at least 48 pt tall")

let primary = between(style, "struct WorkerPrimaryButtonStyle: ButtonStyle {", "\n}\n")
check(!primary.isEmpty && primary.contains("var fill: Color = WorkerStyle.inverse") && primary.contains("var ink: Color = WorkerStyle.onInverse"),
      "the primary button is INVERSE-FILLED by default (the owner's proxy's design call), with the page colour as its label")
check(primary.contains("minHeight: WorkerStyle.buttonMinHeight") && primary.contains("cornerRadius: WorkerStyle.buttonRadius"),
      "the primary button takes its height and radius from the tokens, and its height is a MINIMUM (it grows with Dynamic Type)")
for banned in ["AccentColor", "accentColor", ".tint(", "borderedProminent", ".bordered", "Color(red:", "Color(hex", "UIColor(red", "#"] {
    check(!style.contains(banned), "WorkerStyle.swift has no system-accent button and no hand-typed colour (found '\(banned)')")
}
check(!style.contains(".font(.system(size: 17") && !style.contains(".font(.system(size: 16") && !style.contains(".font(.system(size: 28"),
      "the typography is Dynamic Type text styles, never a fixed point size for text")
check(style.contains("static let title = Font.title.weight(.semibold)") && style.contains("static let rowName = Font.headline"),
      "the heavier titles are SemiBold text styles (Android headlineSmall 28 sp SemiBold, titleMedium SemiBold)")
check(style.contains(".accessibilityHidden(true)") && count(style, "Image(systemName:") == 1,
      "the one local mark is an SF Symbol in a circle and is hidden from VoiceOver")

// The named colour sets carry Android's exact inverse pair (Theme.kt: inverseSurface = TextPrimary,
// inverseOnSurface = BgBase), light and dark, and nothing else decides them.
func assetHex(_ name: String, dark: Bool) -> String? {
    guard let data = FileManager.default.contents(atPath: "NFCTimeSheets/Assets.xcassets/\(name).colorset/Contents.json"),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let colors = root["colors"] as? [[String: Any]] else { return nil }
    for entry in colors {
        let isDark = (entry["appearances"] as? [[String: String]])?.contains { $0["value"] == "dark" } ?? false
        guard isDark == dark,
              let c = (entry["color"] as? [String: Any])?["components"] as? [String: String] else { continue }
        func part(_ k: String) -> String { String((c[k] ?? "??").dropFirst(2)).uppercased() }
        return part("red") + part("green") + part("blue")
    }
    return nil
}
func androidTheme(_ name: String) -> String? {
    guard let kt = try? String(contentsOfFile: "../android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/Theme.kt", encoding: .utf8),
          let r = kt.range(of: "private val \(name) = Color(0xFF") else { return nil }
    return String(kt[r.upperBound...].prefix(6)).uppercased()
}
check(assetHex("WorkerInverse", dark: false) == androidTheme("TextPrimaryLight") && androidTheme("TextPrimaryLight") == "16181C",
      "WorkerInverse (light) is Android's inverseSurface: TextPrimaryLight #16181C (got \(assetHex("WorkerInverse", dark: false) ?? "nil"))")
check(assetHex("WorkerInverse", dark: true) == androidTheme("TextPrimaryDark") && androidTheme("TextPrimaryDark") == "E9EAEC",
      "WorkerInverse (dark) is Android's inverseSurface: TextPrimaryDark #E9EAEC (got \(assetHex("WorkerInverse", dark: true) ?? "nil"))")
check(assetHex("WorkerOnInverse", dark: false) == androidTheme("BgBaseLight") && androidTheme("BgBaseLight") == "FAFAFA",
      "WorkerOnInverse (light) is Android's inverseOnSurface: BgBaseLight #FAFAFA (got \(assetHex("WorkerOnInverse", dark: false) ?? "nil"))")
check(assetHex("WorkerOnInverse", dark: true) == androidTheme("BgBaseDark") && androidTheme("BgBaseDark") == "0B0C0E",
      "WorkerOnInverse (dark) is Android's inverseOnSurface: BgBaseDark #0B0C0E (got \(assetHex("WorkerOnInverse", dark: true) ?? "nil"))")

// Every worker screen's primary action is the shared style, never the system accent. (The sign-in
// code form and Materials are shared with the operator and are the next reskin's; not listed here.)
for name in ["ContentView.swift", "ShiftScreen.swift", "ShiftReceiptView.swift", "DeliveryStatusViews.swift"] {
    let text = code(source(name))
    check(!text.contains("borderedProminent"), "\(name) has no system-accent prominent button: the primary action is WorkerPrimaryButtonStyle")
}
check(count(shiftScreen, ".workerCard()") >= 1 && !shiftScreen.contains("RoundedRectangle(cornerRadius: 16)"),
      "ShiftScreen's one-off card helper is the shared workerCard")

// ---------------------------------------------------------------------------------
// 2. THREE TABS, ALWAYS (worker-nav-three-tabs, tab-labels-shift-and-more, nav-bar-style-and-icons)
// ---------------------------------------------------------------------------------

let tabs = between(content, "TabView(selection: $selection) {", ".id(worker.id)")
check(!tabs.isEmpty, "the TabView has a selection binding (a tap on another tab must be able to select Shift)")
check(tabs.contains("ShiftSignal.visibleTabs(shiftRunning: shiftRunning(for: worker.id)).filter { $0 != .history }"),
      "History is filtered out of what the TabView mounts - ShiftSignal.visibleTabs and AppTab are left alone (shift-signal-check)")
check(!tabs.contains("HistoryView(") && !tabs.contains("Label(\"History\""),
      "no History tabItem is mounted: History is never a tab")
check(inOrder(tabs, ["LogView(worker: worker)", "Label(\"Shift\", systemImage: \"clock\")", ".tag(AppTab.log)",
                     "MaterialsView(worker: worker)", "Label(\"Materials\", systemImage: \"shippingbox\")", ".badge(materials.unseenArrivalCount)", ".tag(AppTab.materials)",
                     "SettingsView(worker: worker)", "Label(\"More\", systemImage: \"ellipsis\")", ".tag(AppTab.settings)"]),
      "the three tabs, in order, with the symbols that match their meaning (Shift: clock, Materials: box, More: ellipsis), the Materials badge unchanged and a stable tag each")
check(!content.contains("Label(\"Log\"") && !content.contains("Label(\"Settings\""),
      "the tab items no longer read 'Log' and 'Settings'")
check(count(content, ".tag(AppTab.") == 3, "exactly three tabs carry a tag")

// A tap that arrives on Materials or More selects Shift; LogView's take() stays the single consumer.
check(content.contains(".onChange(of: inbox.pendingLocationId) { _, id in\n                if id != nil { selection = .log }\n            }"),
      "an arriving tap selects the Shift tab, from the closure's value (never by taking it)")
let outer = between(content, "struct ContentView: View {", "struct SignInView: View {")
check(!outer.contains("inbox.take()") && !outer.contains("handleTap"),
      "the outer view never takes or handles a tap: that stays LogView's (handled once)")
let logView = between(content, "struct LogView: View {", "struct ShiftRow: View {")
check(count(logView, "inbox.take()") == 2, "LogView is still the one consumer: its launch .task and its .onChange are the two takes")
check(content.contains(".onChange(of: worker.id, initial: true) { _, _ in selection = .log }"),
      "a new identity starts on the Shift tab")
check(content.contains("@State private var selection: AppTab = .log"), "the selection is the tab's NAME (AppTab), starting on Shift")
// The TabView's modifiers the receipt and the roster rely on are still on it.
check(inOrder(content, ["TabView(selection: $selection) {", ".id(worker.id)", ".environment(materials)", ".task(id: worker.id) { await materials.start(workerId: worker.id) }",
                        ".sheet(isPresented: $showReceipt, onDismiss: { MigrationReceipt.unseen = false }) {", "MigrationReceiptSheet(shifts: receipt)"]),
      "the migration receipt's .task/.sheet pair is still on the TabView chain")

// ---------------------------------------------------------------------------------
// 3. HISTORY LIVES UNDER MORE (history-under-more)
// ---------------------------------------------------------------------------------

let history = between(content, "struct HistoryView: View {", "struct SettingsView: View {")
check(!history.isEmpty && !history.contains("NavigationStack"),
      "HistoryView has no NavigationStack of its own: it is pushed, and a second stack would draw two navigation bars")
check(history.contains(".navigationTitle(\"History\")") && history.contains(".onDelete {"),
      "...keeps its title and its (iOS-only) swipe-to-delete")
let settings = between(content, "struct SettingsView: View {", "\n}\n")
check(settings.contains("@Query private var allShifts: [Shift]") && settings.contains("private var shiftOpen: Bool { allShifts.openShift(for: worker.id) != nil }"),
      "More asks WorkerScope whether THIS worker has an open shift (never another account's forgotten row)")
check(inOrder(settings, ["NavigationLink(\"My hours\") { MyHoursView(worker: worker) }", "if !shiftOpen {",
                         "NavigationLink(\"History\", value: SettingsRoute.history)", "Hours, locations and payroll are managed"]),
      "the History row sits in the identity section after My hours and exists only while no shift is open")
check(inOrder(settings, ["NavigationStack(path: $path) {", ".navigationDestination(for: SettingsRoute.self) { route in", "case .history: HistoryView(worker: worker)",
                         ".onChange(of: shiftOpen) { _, open in", "if open { path.removeAll() }"]),
      "a shift that starts pops History")
check(settings.contains(".navigationTitle(\"Settings\")"), "the heading inside More stays 'Settings' (Android settings_title)")
check(count(content, "HistoryView(worker: worker)") == 1, "History is built in exactly one place")

// ---------------------------------------------------------------------------------
// 3b. THE IDLE SCREEN (TASK-365.10: idle-day-heading, idle-start-card, idle-layout-order,
//     shift-row-card-restyle, shift-row-waiting-copy)
// ---------------------------------------------------------------------------------

let home = code(source("WorkerHomeViews.swift"))
let idle = between(content, "private var idleList: some View {", "#if DEBUG\n            manualMockSection")
check(!idle.isEmpty, "found the idle list")
check(home.contains("struct WorkerDayHeading: View {") && home.contains("TimelineView(.everyMinute)")
      && home.contains("formatter.dateFormat = \"EEEE · d MMMM\"") && home.contains("Text(\"Your working day\")")
      && home.contains(".accessibilityAddTraits(.isHeader)"),
      "the heading is Android's date line (EEEE · d MMMM, in the app's locale, re-read each minute) and 'Your working day' as a VoiceOver header")
check(home.contains("Text(verbatim: Self.dateLine(context.date, locale: locale))"), "the date line is data: verbatim, never a catalogue key")

// ORDER, top to bottom: heading, unresolved banner, receipt-or-start block, delivery rows, plan, Recent, mocks, no-push note.
check(inOrder(idle, ["WorkerDayHeading()", "if !unresolved.isEmpty {", "if let receiptShift {", "if receiptShift == nil {",
                     "DeliveryStatusRows(rows: deliveryRows, signedOut: false)", "ScheduleSummary(state: schedule.state, retry: loadSchedule)",
                     "Section(\"Recent\") {", "ForEach(recentRows)"])
      && inOrder(between(content, "private var idleList: some View {", ".workerListPage()"),
                 ["Section(\"Recent\") {", "manualMockSection", "This app has no push. Everything you see here updates when you open it."]),
      "idle order: day heading, unresolved banner, receipt or start card, delivery rows, planned assignment, Recent, (debug mocks), no-push note - the ACTION first")
check(content.contains("private var navigationTitle: LocalizedStringKey {\n        running == nil ? \"\" : \"Shift running\"\n    }")
      && content.contains(".navigationTitle(navigationTitle)") && !content.contains("\"TimeSheet\""),
      "the idle navigation title is EMPTY (the first row is the heading) and the running title is a LocalizedStringKey, never a ternary of two literals (TASK-298)")
check(inOrder(between(content, "private var idleList: some View {", ".onChange(of: recent.first?.receiptIdentity"), [".workerListPage()", ".tint(.primary)"]),
      "the idle list is monochrome chrome: its text buttons are the ink, not the system accent")
check(!idle.contains("Button(\"Refresh\"") && !idle.contains("Button(\"Refresh"),
      "no Refresh button on the idle list: pull-to-refresh is the refresh control (Android has the button, iOS has the gesture)")
check(content.contains(".refreshable { await refresh() }"), "pull-to-refresh is still wired to refresh()")

// THE START BLOCK: one glyph, the question, the hint, ONE filled scan button, a quiet manual start.
let start = between(idle, "if receiptShift == nil {", "DeliveryStatusRows(")
check(inOrder(start, ["WorkerGlyph(systemName: \"iphone.radiowaves.left.and.right\")", "Text(\"Ready for your shift?\")",
                      "Text(\"Hold your phone to the tag by the entrance to start.\")", "Button(action: scan) {", ".buttonStyle(.workerPrimary)",
                      "Button(\"Start without a tag\") {", ".buttonStyle(.workerQuiet)"]),
      "the start block reads: mark, 'Ready for your shift?', the hint, ONE filled scan button, a quiet 'Start without a tag'")
check(count(start, ".workerPrimary") == 1 && !start.contains(".bordered") && !start.contains("borderedProminent"),
      "exactly one filled button in the start block, and the manual start is not a second one")
check(!idle.contains("Section {"), "no stock grouped Section is left around the start block, the delivery rows or the plan")
check(count(idle, "showManualStart = true") == 1 && count(idle, "manualPick = nil") == 1,
      "the manual start still resets its pick and opens the sheet (decision-56 / 81 behaviour untouched)")

// ROWS: cards, the range dominant, the 'Manual' pill kept, never 'Sending...'.
let row = between(content, "struct ShiftRow: View {", "func pill(")
check(!row.isEmpty && row.contains(".workerCard()") && row.contains(".workerListRow()"),
      "a shift row is a worker card on a chrome-free list row (History's swipe-to-delete still has a row to swipe)")
check(inOrder(row, ["Text(verbatim: name)", "pill(\"Manual\", .blue)", "formatted(date: .abbreviated, time: .omitted)",
                    "Text(\"\\(shift.startTime.formatted(date: .omitted, time: .shortened)) – \\(end.formatted(date: .omitted, time: .shortened))\")",
                    ".font(WorkerStyle.Typeface.lead)", "Text(verbatim: fmtDur(d))", "syncStatus"]),
      "a row reads: name and pills, date, the time RANGE in the lead style, the duration, the delivery line")
check(!row.contains("Sending…"), "a row never says 'Sending…' (Android: an unsent row is WAITING)")
check(inOrder(row, ["Label(\"Sent\"", "Label(\"Waiting for a connection\"", "shift.lastAttemptAt",
                    "Text(\"Last tried \\(attempt.formatted(date: .omitted, time: .shortened))\")", "Text(\"Not attempted yet\")"]),
      "an unsent row says 'Waiting for a connection' and either 'Last tried HH:mm' or 'Not attempted yet'")
check(content.contains("func fmtDur(_ s: TimeInterval) -> String { \"\\(Int(s) / 3600)h \\((Int(s) % 3600) / 60)m\" }"), "fmtDur is unchanged")

// THE LAST ATTEMPT: an optional field on the row, stamped where the request leaves the phone, never read by a decision.
let model = code(source("NFCTimeSheetsApp.swift"))
let sync = code(source("Sync.swift"))
check(model.contains("var lastAttemptAt: Date?"), "Shift has an OPTIONAL lastAttemptAt (SwiftData's lightweight migration adds it)")
check(inOrder(between(sync, "private func pushOpen(", "\n}"), ["DeliveryAttempt.stamp()", "shift.lastAttemptAt = .now", "try await ShiftFlowAPI.open("])
      && inOrder(between(sync, "private func pushClose(", "\n}"), ["DeliveryAttempt.stamp()", "shift.lastAttemptAt = .now", "try await ShiftFlowAPI.close("]),
      "pushOpen and pushClose stamp the row right where they stamp the device-wide attempt, before the request")
check(inOrder(between(content, ".sheet(item: $proofShift", "// Coming back from the background"), ["DeliveryAttempt.stamp()", "shift.lastAttemptAt = .now", "try await ShiftAPI.close("]),
      "the proof-close stamps the row too")
check(count(sync, "lastAttemptAt") == 2 && count(model, "lastAttemptAt") == 1,
      "lastAttemptAt is only WRITTEN in the sync engine: no retry decision reads it")
for name in ["ShiftReceipt.swift", "PendingNotice.swift", "ShiftSignal.swift", "ShiftSignalCenter.swift"] {
    check(!code(source(name)).contains("lastAttemptAt"), "\(name) does not know the per-row attempt exists (display only)")
}

// ---------------------------------------------------------------------------------
// 4. STRINGS: BOTH LANGUAGES, in the same commit (AGENTS.md i18n)
// ---------------------------------------------------------------------------------

guard let catalogueData = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
      let catalogueRoot = try? JSONSerialization.jsonObject(with: catalogueData) as? [String: Any],
      let catalogue = catalogueRoot["strings"] as? [String: Any]
else { print("FAIL: Localizable.xcstrings unreadable"); exit(1) }

func value(_ key: String, _ lang: String) -> String? {
    let loc = (((catalogue[key] as? [String: Any])?["localizations"] as? [String: Any])?[lang] as? [String: Any])
    if let unit = loc?["stringUnit"] as? [String: Any] { return unit["value"] as? String }
    // a plural variation: its "other" form is the sentence
    return (((loc?["variations"] as? [String: Any])?["plural"] as? [String: Any])?["other"] as? [String: Any])
        .flatMap { $0["stringUnit"] as? [String: Any] }.flatMap { $0["value"] as? String }
}
func androidString(_ name: String, en: Bool = false) -> String? {
    let file = en ? "values-en" : "values"
    guard let xml = try? String(contentsOfFile: "../android/app/src/main/res/\(file)/strings.xml", encoding: .utf8) else { return nil }
    let open = "<string name=\"\(name)\">"
    guard let start = xml.range(of: open), let end = xml.range(of: "</string>", range: start.upperBound..<xml.endIndex) else { return nil }
    return String(xml[start.upperBound..<end.lowerBound])
        .replacingOccurrences(of: "\\'", with: "'")
        .replacingOccurrences(of: "%1$s", with: "%@")
}

/// (key, Android string resource) for every sentence this reskin ADDS. Both languages must be in the
/// catalogue and both must be Android's own words - the same house vocabulary on both phones.
let added: [(String, String)] = [
    // B1
    ("Shift", "nav_shift"),
    ("More", "nav_more"),
    // B2
    ("Your working day", "worker_day_title"),
    ("Ready for your shift?", "worker_start_title"),
    ("Waiting for a connection", "sync_waiting"),
    ("Last tried %@", "sync_last_try"),
    ("Not attempted yet", "sync_never_tried"),
]
for (key, androidName) in added {
    check(value(key, "de") != nil && value(key, "de") == androidString(androidName),
          "'\(key)' has Android's German '\(androidString(androidName) ?? "?")' verbatim (\(androidName)); got '\(value(key, "de") ?? "nil")'")
    check(value(key, "en") != nil && value(key, "en") == androidString(androidName, en: true),
          "'\(key)' has an explicit English entry that is Android's '\(androidString(androidName, en: true) ?? "?")' (\(androidName)); got '\(value(key, "en") ?? "nil")'")
}
check(catalogue["Log"] == nil, "the dead tab label 'Log' is gone from the catalogue")
check(catalogue["TimeSheet"] == nil, "the idle navigation title 'TimeSheet' is gone from the catalogue (nothing uses it)")
check(catalogue["Tag missing or unreachable? Pick the zone instead. The office sees this as a manual entry."] == nil,
      "the manual start's idle footer is gone: the explanation lives in the sheet and the confirmation dialog")

if failed { exit(1) }
print("worker-reskin-check: OK")
