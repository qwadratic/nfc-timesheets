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
// WHAT IT GUARDS, by section: 1 the shared tokens (WorkerStyle.swift, Android's inverse pair in the asset
// catalogue); 2 three tabs always and the tap-arrival rule; 3 History under More; 3b the idle screen (day
// heading, start block, order, row cards, "Waiting for a connection", the per-row attempt stamp); 3c the
// running screen (the fixed field, the typographic time, the quiet header, help behind a button); 4 every
// string this reskin adds, in both languages, as Android's own words.
//
// RED CASES reproduced before this was trusted (see the three commits): the History tab put back into the
// ForEach; `.borderedProminent` back on the idle Scan button; `Label("Log"` restored; `selection = .log`
// dropped from the tap arrival; a WorkerInverse / ShiftField colour edited to another hex; a NavigationStack
// back inside HistoryView; the History row shown mid-shift; "Sending..." back in a row; the idle footer or a
// Refresh button back; the stamp dropped from pushOpen; a card behind the time; `Text(timerInterval:)` back;
// a green or raw-blue literal on the running screen; the digits' timeline slowed to a minute; the neutral
// cards drawn in the field's scheme; the help sentence printed again; one new key left without its English.

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
check(!primary.isEmpty && primary.contains("let fillColor = fill ?? onField?.ink ?? WorkerStyle.inverse")
      && primary.contains("let labelColor = ink ?? onField?.field ?? WorkerStyle.onInverse"),
      "the primary button is INVERSE-FILLED by default (the owner's proxy's design call), with the page colour as its label - and inverts against a field when it sits on one")
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
check(content.contains(".navigationTitle(\"\")\n            .navigationBarTitleDisplayMode(.inline)")
      && !content.contains("\"TimeSheet\"") && !content.contains("\"Shift running\""),
      "neither screen has a navigation title (the idle heading and the running state heading are the titles) and the bar stays, empty and inline")
check(inOrder(between(content, "private var idleList: some View {", ".onChange(of: recent.first?.receiptIdentity"), [".workerListPage()", ".tint(Color.primary)"]),
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
// 3c. THE RUNNING SCREEN (TASK-365.11: running-field-fixed-dark-blue, running-time-display,
//     running-header-hierarchy, running-help-dialog)
// ---------------------------------------------------------------------------------

let digitsFile = code(source("ShiftTimeDisplay.swift"))
let clockBlock = between(shiftScreen, "private func clock(presentation: ShiftPresentation, now: Date) -> some View {",
                         "\n    private func instruction(tint: Color) -> some View {")

// THE FIELD: fixed named colours, Android's values, the same in light and dark.
func androidBrand(_ name: String) -> String? {
    guard let kt = try? String(contentsOfFile: "../android/app/src/main/kotlin/io/github/qwadratic/nfctimesheets/ui/Theme.kt", encoding: .utf8),
          let shiftBrand = kt.range(of: "object ShiftBrand {"),
          let r = kt.range(of: "val \(name) = Color(0xFF", range: shiftBrand.upperBound..<kt.endIndex) else { return nil }
    return String(kt[r.upperBound...].prefix(6)).uppercased()
}
check(assetHex("ShiftField", dark: false) == "10243D" && assetHex("ShiftField", dark: true) == "10243D" && androidBrand("Container") == "10243D",
      "the field is ShiftBrand.Container #10243D in BOTH appearances (got \(assetHex("ShiftField", dark: false) ?? "nil")/\(assetHex("ShiftField", dark: true) ?? "nil"))")
check(assetHex("ShiftOnField", dark: false) == "E6ECF5" && assetHex("ShiftOnField", dark: true) == "E6ECF5" && androidBrand("OnContainer") == "E6ECF5",
      "the ink is ShiftBrand.OnContainer #E6ECF5 in BOTH appearances")
check(assetHex("ShiftOverdueField", dark: false) == androidTheme("BgOverlayLight") && assetHex("ShiftOverdueField", dark: true) == androidTheme("BgRaisedDark"),
      "the overdue field is Android's errorContainer: BgOverlayLight / BgRaisedDark")
check(assetHex("ShiftOverdueInk", dark: false) == androidTheme("ErrorLight") && assetHex("ShiftOverdueInk", dark: true) == androidTheme("ErrorDark"),
      "the overdue ink is Android's onErrorContainer: ErrorLight / ErrorDark - the one colour that still carries a consequence")
for named in ["ShiftField", "ShiftOnField", "ShiftOverdueField", "ShiftOverdueInk", "ShiftRunning"] {
    check(shiftScreen.contains("Color(\"\(named)\")"), "ShiftScreen draws with the NAMED set '\(named)' (decision-60 section 1: never a literal)")
}
// decision-60: no green, no raw blue, no literal colour for the field.
for banned in [".green", "Color.green", ".blue", "Color.blue", "Color(red:", "Color(white:", "Color(hue:", "UIColor(", "Color(.sRGB"] {
    check(!shiftScreen.contains(banned) && !digitsFile.contains(banned), "the running screen has no '\(banned)' (decision-60: never green, the field is a named set)")
}
let onFieldHelper = between(shiftScreen, "func onField(ink: Color, field: Color, scheme: ColorScheme) -> some View {", "\n    }\n}")
check(inOrder(onFieldHelper, [".foregroundStyle(ink)", ".tint(ink)", ".environment(\\.workerField, WorkerField(field: field, ink: ink))",
                              ".environment(\\.colorScheme, scheme)"])
      && shiftScreen.contains("let scheme: ColorScheme = neutral ? systemScheme : .dark")
      && shiftScreen.contains(".toolbarColorScheme(neutral ? nil : .dark, for: .navigationBar)"),
      "a piece on the field is drawn in its ink, tint and field/ink pair (what the buttons invert against) in a DARK scheme - the phone's own only on the overdue-neutral field - and the status bar icons are light")
// ...applied PIECE BY PIECE: the stack itself and the ScrollView carry no foreground style, tint or scheme, because the delivery
// rows' sheet and the neutral cards would inherit them (a sheet keeps the phone's light background under light ink).
let runningStack = between(shiftScreen, "VStack(spacing: 24) {", ".frame(maxWidth: .infinity)")
check(count(runningStack, ".onField(ink: tint, field: field, scheme: scheme)") == 7,
      "seven pieces are drawn on the field: header, time, notice, instruction, scan, quiet finish, help (got \(count(runningStack, ".onField(")))")
let afterStack = between(shiftScreen, ".padding(24)\n            }", ".toolbarColorScheme")
check(!afterStack.contains(".foregroundStyle(") && !afterStack.contains(".tint(") && !afterStack.contains(".environment(\\.colorScheme"),
      "nothing is applied to the whole ScrollView: a sheet presented from inside it would inherit light ink and a dark scheme over the phone's light sheet")
check(inOrder(runningStack, ["DeliveryStatusRows(rows: deliveryRows, signedOut: false)", ".tint(tint)", "if signals.outOfAppSignalsSilenced { notificationsOffCard }"])
      && !between(runningStack, "DeliveryStatusRows(rows: deliveryRows, signedOut: false)", "if signals.outOfAppSignalsSilenced").contains(".onField("),
      "the delivery rows get the ink as their TINT only, so the sheet they present reads in the phone's own appearance")
check(shiftScreen.contains("let neutral = overdue && !funTheme") && shiftScreen.contains("let tint: Color = overdue ? Self.overdueInk : Self.onField")
      && shiftScreen.contains("let field: Color = neutral ? Self.overdueField : Self.field"),
      "overdue is red ink (on the neutral field with the flag off, over the blue with it on); running is the fixed field and light ink")
check(shiftScreen.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion") && shiftScreen.contains("if funTheme && !reduceMotion {"),
      "Reduce Motion: the animated gradient holds still (the field alone is a complete screen)")
check(shiftScreen.contains("BlueDrift(tint: overdue ? .red : Self.running)") && shiftScreen.contains("@AppStorage(FeatureFlags.defaultsKey(FeatureFlags.funShiftScreen))"),
      "the flag-gated animated gradient is kept (decision-60 section 3), drawn over the field")
// NO TIMER CARD, no card behind the instruction: the only surfaces left are the neutral cards.
check(!clockBlock.isEmpty && !clockBlock.contains(".background(") && !clockBlock.contains("RoundedRectangle") && !clockBlock.contains("workerCard"),
      "the time has no card behind it (the white timer card is gone)")
let instructionBlock = between(shiftScreen, "private func instruction(tint: Color) -> some View {", "\n    private var scanButton: some View {")
check(!instructionBlock.isEmpty && !instructionBlock.contains(".background(") && !instructionBlock.contains("RoundedRectangle") && !instructionBlock.contains("workerCard"),
      "the tap instruction has no card behind it either")
let cardHelper = between(shiftScreen, "private func card(icon: String, tint: Color, @ViewBuilder content: () -> some View) -> some View {", "\n    }\n}")
check(cardHelper.contains(".workerCard()") && !cardHelper.contains(".onField(") && !cardHelper.contains("colorScheme"),
      "the notice, resolver, notifications and plan blocks stay NEUTRAL cards in the phone's own appearance, with no field-relative buttons inside")
check(count(shiftScreen, "private func card(") == 1 && count(shiftScreen, ".workerCard()") == 1,
      "one card helper, built on the shared worker card")
check(shiftScreen.contains(".buttonStyle(.workerPrimary)") && shiftScreen.contains(".buttonStyle(.workerQuiet)") && !shiftScreen.contains("borderedProminent"),
      "Scan is the one filled button (inverted against the field); finishing without a tag is a quiet text button behind its confirmation dialog")
check(shiftScreen.contains(".confirmationDialog(Text(\"Finish your shift at \\(running.locationName) now?\")") && shiftScreen.contains("Button(\"Finish now\", role: .destructive, action: onManualStop)"),
      "decision-56: the manual stop still asks first and names the building")

// THE TIME: label, HH:MM large, seconds small, one accessibility element, ticking in its own timeline.
check(inOrder(clockBlock, ["Text(\"TIME WORKED\")", "ShiftTimeDigits(startTime: running.startTime, overdue: presentation == .overdue)",
                           "stateWord(presentation)", ".confirmationMotion(", ".accessibilityElement(children: .ignore)",
                           ".accessibilityLabel(spokenState(presentation, elapsed: elapsed))"]),
      "the time block reads: 'TIME WORKED', the digits, the state word - one accessibility element with the spoken label, the confirmation motion untouched")
check(digitsFile.contains("TimelineView(.periodic(from: startTime, by: 1))") && digitsFile.contains(".accessibilityHidden(true)")
      && digitsFile.contains("@ScaledMetric(relativeTo: .largeTitle)") && digitsFile.contains(".monospacedDigit()")
      && digitsFile.contains("size * 0.32") && digitsFile.contains(".minimumScaleFactor(0.4)"),
      "the digits tick once a second in their OWN timeline, are hidden from VoiceOver, tabular, follow Dynamic Type and fit the width, the seconds at 32%")
check(digitsFile.contains("ShiftSignal.clockParts(from: startTime, to: context.date)") && digitsFile.contains("ShiftSignal.overdueClock"),
      "the digits are ShiftSignal.clockParts (clamped at 8 h) or the overdue clock")
check(!digitsFile.contains("Text(\"") && !digitsFile.contains("String(localized:") && !digitsFile.contains(".background(") && !digitsFile.contains("foregroundStyle"),
      "the digits carry no words, no surface and no ink of their own")

// THE HEADER: a quiet state heading, the building one step down, the start time.
let headerBlock = between(shiftScreen, "private func header(presentation: ShiftPresentation, tint: Color) -> some View {", "\n    /// The dominant element")
check(inOrder(headerBlock, ["headingText(presentation)", ".font(WorkerStyle.Typeface.label)", ".accessibilityAddTraits(.isHeader)",
                            "Text(running.locationName)", ".font(.title2.weight(.medium))", "Text(\"Started \\(running.startTime.formatted(date: .omitted, time: .shortened))\")"]),
      "the header is a quiet label-weight state heading, the site at title2 medium, then 'Started HH:mm'")
check(shiftScreen.contains("case .running: return Text(\"Shift in progress\")"), "running says 'Shift in progress' (Android worker_active_title), not 'Clocked in'")

// THE HELP: behind a labelled button, never printed, never an alert.
check(shiftScreen.contains("DisclosureGroup(isExpanded: $showHelp) {") && shiftScreen.contains("Text(\"Shift help\")")
      && inOrder(shiftScreen, ["DisclosureGroup(isExpanded: $showHelp) {", "Something wrong? Ask what to do", "Text(\"Shift help\")"]),
      "the help sentence is inside a disclosure labelled 'Shift help'")
check(count(shiftScreen, "Something wrong? Ask what to do") == 1 && !shiftScreen.contains("helpCard"),
      "the sentence is printed in exactly one place and the always-visible help card is gone")
check(!shiftScreen.contains(".alert(") && !shiftScreen.contains(".sheet("),
      "help is not an alert or a second sheet: SwiftUI drops one of those when the decision-10 resolver sheet presents")
check(inOrder(between(shiftScreen, "VStack(spacing: 24) {", ".frame(maxWidth: .infinity)"), ["scheduleCard", "helpButton"]),
      "the help button is the last thing on the running screen, after the plan")

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
    // B3
    ("Shift in progress", "worker_active_title"),
    ("TIME WORKED", "worker_elapsed"),
    ("Shift help", "worker_help"),
]
for (key, androidName) in added {
    check(value(key, "de") != nil && value(key, "de") == androidString(androidName),
          "'\(key)' has Android's German '\(androidString(androidName) ?? "?")' verbatim (\(androidName)); got '\(value(key, "de") ?? "nil")'")
    check(value(key, "en") != nil && value(key, "en") == androidString(androidName, en: true),
          "'\(key)' has an explicit English entry that is Android's '\(androidString(androidName, en: true) ?? "?")' (\(androidName)); got '\(value(key, "en") ?? "nil")'")
}
check(catalogue["Log"] == nil, "the dead tab label 'Log' is gone from the catalogue")
check(catalogue["Clocked in"] == nil && catalogue["Shift running"] == nil,
      "the retired running heading 'Clocked in' and the nav title 'Shift running' are gone (nothing uses them; 'eingestempelt' lives on elsewhere)")
check(catalogue["TimeSheet"] == nil, "the idle navigation title 'TimeSheet' is gone from the catalogue (nothing uses it)")
check(catalogue["Tag missing or unreachable? Pick the zone instead. The office sees this as a manual entry."] == nil,
      "the manual start's idle footer is gone: the explanation lives in the sheet and the confirmation dialog")

if failed { exit(1) }
print("worker-reskin-check: OK")
