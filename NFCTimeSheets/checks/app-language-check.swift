// Runnable check: the in-app language (decision-74, TASK-365.14 / .15 / .16).
//
//   cd NFCTimeSheets && cat NFCTimeSheets/AppLanguage.swift checks/app-language-check.swift > /tmp/al.swift \
//     && swift /tmp/al.swift          (or: ./checks/run.sh)
//
// AppLanguage.swift is Foundation-only and is cat-ed in, so the RULES run for real: the value set, how a
// stored OS value becomes a selection, what "follow the phone" resolves to (and what a phone in neither
// language gets), the locale that dates and numbers use, persistence through an injected store (the OS
// per-app value, never a second flag), the notification, string resolution against a throwaway bundle of
// de.lproj / en.lproj, and rerender - a stored sentence said again in the language in force.
//
// The sources, the string catalogue and the other checks' wiring are read off disk as TEXT (the same way
// worker-reskin-check.swift does), because what has to be pinned there is not a value but a PLACE:
//
//   1 the bypasses are banned - a `String(localized:)`, `NSLocalizedString`, a bundle lookup, a
//     `Locale.current`, `Locale.preferredLanguages` or the OS key outside AppLanguage.swift is a build-time
//     failure of THIS file, the way localisation-check fails on a missing German entry (decision-74 rule 6);
//   2 the stored sentences are drawn through rerender (the list below names every display site);
//   3 the language reaches the screens through the root environment and NEVER by recreating the tree;
//   4 the real catalogue, loaded the way the app loads it, answers rerender in both directions.
//
// RED CASES reproduced before this was trusted: a `String(localized:)` put back into API.swift; a
// `Locale.current` default back on ViennaTime.date; `.appLanguage()` removed from the app; `.id(` on the
// language added to ContentView; the OS key written through a second flag; `set("fr")` accepted;
// "follow the phone" stored as "" instead of removed; a rerender site reverted to `Text(verbatim: sentence)`.

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
func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

// ---------------------------------------------------------------------------------
// 1. The value set
// ---------------------------------------------------------------------------------

check(AppLanguage.supported.sorted() == ["de", "en"], "the app has exactly German and English")
check(AppLanguage.options == ["de", "en", ""], "the picker's order is Deutsch, English, follow the phone (Android LanguagePicker)")
check(AppLanguage.isValid("") && AppLanguage.isValid("de") && AppLanguage.isValid("en"), "'', 'de', 'en' are the value set")
for bad in ["fr", "DE", "de-AT", "system", " ", "en "] {
    check(!AppLanguage.isValid(bad), "'\(bad)' is not a selection (Android: require(language in listOf(\"\", \"de\", \"en\")))")
}
check(AppLanguage.overrideKey == "AppleLanguages",
      "the stored value is the OS's per-app key, not a key of ours (decision-74 rule 3: one value, shared with iOS Settings)")

// ---------------------------------------------------------------------------------
// 2. Stored OS value -> selection
// ---------------------------------------------------------------------------------

for (stored, want) in [(nil, ""), ([], ""), (["de"], "de"), (["en"], "en"), (["de-AT"], "de"), (["de_AT"], "de"),
                       (["EN-gb"], "en"), (["fr"], ""), (["fr-FR", "de"], ""), (["de", "en"], "de"), ([""], "")] as [([String]?, String)] {
    check(AppLanguage.selection(fromStored: stored) == want,
          "stored \(stored.map { "\($0)" } ?? "nil") reads as '\(want)' (got '\(AppLanguage.selection(fromStored: stored))')")
}

// ---------------------------------------------------------------------------------
// 3. Selection -> the language in force
// ---------------------------------------------------------------------------------

func effective(_ selection: String, _ preferred: [String], dev: String? = "en") -> String {
    AppLanguage.effective(selection: selection, preferred: preferred, developmentLanguage: dev)
}
check(effective("de", ["en-US"]) == "de", "a choice of German wins over an English phone")
check(effective("en", ["de-AT", "en"]) == "en", "a choice of English wins over a German phone")
check(effective("", ["de-AT", "en"]) == "de", "follow the phone: German phone, German")
check(effective("", ["en-AT", "ru-AT"]) == "en", "follow the phone: English phone, English (this Simulator's own pair)")
check(effective("", ["fr-FR", "de-AT"]) == "de", "follow the phone: the first of the phone's languages that the app HAS, as iOS matches a bundle")
check(effective("", ["fr-FR", "en-US"]) == "en", "follow the phone: French then English is English")
check(effective("", ["fr-FR"]) == "en", "a phone in neither language gets the development language (en today; TASK-327 owns it)")
check(effective("", ["fr-FR"], dev: "de") == "de", "...and when the owner moves the development region to de, this follows without an edit here")
check(effective("", [], dev: nil) == "en", "no preferences and no development language is English, never a crash")
check(effective("", ["fr"], dev: "zz") == "en", "an unsupported development language is not trusted")
check(effective("fr", ["de"]) == "de", "an unsupported selection is not a choice (it is read as 'follow the phone')")

// The locale dates and numbers use.
let systemAT = Locale(identifier: "de_AT")
check(AppLanguage.locale(selection: "", effective: "de", system: systemAT).identifier == "de_AT",
      "follow the phone on a German phone IS the phone's locale, region and all (exactly what iOS did before)")
check(AppLanguage.locale(selection: "", effective: "en", system: Locale(identifier: "fr_FR")).identifier == "en",
      "a French phone that fell back to English formats in English, not half in each")
check(AppLanguage.locale(selection: "en", effective: "en", system: systemAT).identifier == "en",
      "an explicit choice is the BARE language (Android: Locale.forLanguageTag(\"en\")), not the phone's region")
check(AppLanguage.locale(selection: "de", effective: "de", system: Locale(identifier: "en_US")).identifier == "de",
      "an explicit German on an English phone formats German")
check(AppLanguage.primary(of: "de_AT") == "de" && AppLanguage.primary(of: "EN-us") == "en", "region and case are stripped")

// ---------------------------------------------------------------------------------
// 4. Persistence: ONE value, the OS's, behind a seam
// ---------------------------------------------------------------------------------

final class MemoryStore {
    var value: [String]?
    var writes: [[String]?] = []
}
let memory = MemoryStore()
func installPhone(_ preferred: [String], system: String = "de_AT", dev: String? = "en", stored: [String]? = nil) {
    memory.value = stored
    memory.writes = []
    AppLanguage.useForTesting(
        store: AppLanguage.Store(read: { memory.value }, write: { memory.value = $0; memory.writes.append($0) }),
        preferred: preferred, system: Locale(identifier: system), developmentLanguage: dev)
}

var notified = 0
let token = NotificationCenter.default.addObserver(forName: AppLanguage.didChange, object: nil, queue: nil) { _ in notified += 1 }

installPhone(["de-AT", "en"])
check(AppLanguage.selection == "" && AppLanguage.effective == "de", "nothing stored: follow the phone, German")
check(AppLanguage.set("en") && memory.value == ["en"], "choosing English stores the OS key as [\"en\"]")
check(AppLanguage.selection == "en" && AppLanguage.effective == "en", "...and applies at once (no relaunch)")
check(AppLanguage.locale.identifier == "en", "...and the locale is the bare language")
check(notified == 1, "...and says so once")
check(AppLanguage.set("en") && notified == 1, "choosing what is already chosen says nothing")
check(AppLanguage.set("de") && memory.value == ["de"] && AppLanguage.effective == "de", "German")
check(AppLanguage.set("") && memory.value == nil && memory.writes.last! == nil,
      "'follow the phone' REMOVES the override - it is never stored as a third state")
check(AppLanguage.selection == "" && AppLanguage.effective == "de", "...and the phone's own language is back")
let writesBefore = memory.writes.count
check(!AppLanguage.set("fr") && !AppLanguage.set("DE") && !AppLanguage.set("system") && memory.writes.count == writesBefore,
      "a value outside the set is refused and writes nothing")

// Survives a relaunch: the next process reads what the OS key holds.
installPhone(["en-US"], system: "en_US", stored: ["de"])
check(AppLanguage.selection == "de" && AppLanguage.effective == "de",
      "a new process reads the stored choice: German on an English phone, relaunch-proof")
// A value written by iOS Settings (per-app language) shows as selected, and the reverse.
installPhone(["de-AT"], stored: ["en-AT"])
check(AppLanguage.selection == "en", "a language set in iOS Settings (any regional tag) shows as the selected one")
// ...and a change made behind the app's back is picked up on the next foreground.
notified = 0
memory.value = ["de"]
AppLanguage.refresh()
check(AppLanguage.selection == "de" && notified == 1, "refresh() reads the OS value again and tells the app once")
AppLanguage.refresh()
check(notified == 1, "...and says nothing when nothing changed")
NotificationCenter.default.removeObserver(token)

// A launch argument (-AppleLanguages (de)) is the PHONE speaking, not a selection: the UI tests rely on it.
installPhone(["de"], system: "en_GB")
check(AppLanguage.selection == "" && AppLanguage.effective == "de", "an argument-domain language is followed, and is not a stored choice")

// ---------------------------------------------------------------------------------
// 5. Strings resolve in the language, whatever language the process is in
// ---------------------------------------------------------------------------------

let work = FileManager.default.temporaryDirectory.appendingPathComponent("app-language-check-\(UUID().uuidString)")
func writeTable(_ language: String, _ text: String) {
    let dir = work.appendingPathComponent("\(language).lproj")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! text.write(to: dir.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
}
writeTable("de", """
"Hello %@" = "Hallo %@";
"Still clocked in" = "Noch eingestempelt";
"Only German has this" = "Nur Deutsch";
"Rejected by the server (%@). Ask your admin." = "Vom Server abgelehnt (%@). Bitte fragen Sie Ihre Verwaltung.";
"No connection - will send when you're back online." = "Keine Verbindung - wird gesendet, sobald Sie wieder online sind.";
"Shift at %@ ended %@" = "Schicht in %2$@ endete um %1$@";
"%@ at %@" = "%1$@ in %2$@";
"Cancel" = "Abbrechen";
"Close" = "Abbrechen";
""")
writeTable("en", """
"Hello %@" = "Hello %@";
"Rejected by the server (%@). Ask your admin." = "Rejected by the server (%@). Ask your admin.";
"Shift at %@ ended %@" = "Shift at %@ ended %@";
"Cancel" = "Cancel";
"Close" = "Close";
""")
let bundle = Bundle(url: work)!
func resource(_ name: String) -> LocalizedStringResource {
    LocalizedStringResource("Hello \(name)", bundle: .atURL(work))
}
check(AppLanguage.string(resource("Anna"), language: "de") == "Hallo Anna", "string(): German")
check(AppLanguage.string(resource("Anna"), language: "en") == "Hello Anna", "string(): English")
check(AppLanguage.string(LocalizedStringResource("Only German has this", bundle: .atURL(work)), language: "en") == "Only German has this",
      "a key the English table does not carry is its own English text (the source language is not written out)")
check(AppLanguage.string(LocalizedStringResource("Only German has this", bundle: .atURL(work)), language: "de") == "Nur Deutsch",
      "...and German finds its entry")
installPhone(["de-AT"])
check(AppLanguage.string(resource("Anna"), locale: Locale(identifier: "en_AT")) == "Hello Anna" &&
      AppLanguage.string(resource("Anna"), locale: Locale(identifier: "de")) == "Hallo Anna",
      "string(locale:) reads the language of a view's \\.locale, region ignored")
check(AppLanguage.string(resource("Anna"), locale: Locale(identifier: "fr_FR")) == "Hallo Anna",
      "a locale in neither language is read as the language in force")
check(AppLanguage.string(resource("Anna")) == "Hallo Anna", "string(): the language in force (German phone)")
check(AppLanguage.language(of: Locale(identifier: "en_GB")) == "en", "language(of:) is the primary subtag")

// ---------------------------------------------------------------------------------
// 6. rerender: a sentence said earlier, said again
// ---------------------------------------------------------------------------------

AppLanguage.useCatalogueForTesting(bundle: bundle)
func again(_ text: String, _ language: String) -> String { AppLanguage.rerender(text, language: language) }
check(again("No connection - will send when you're back online.", "de") == "Keine Verbindung - wird gesendet, sobald Sie wieder online sind.",
      "an English sentence stored by a row is said in German after a switch")
check(again("Keine Verbindung - wird gesendet, sobald Sie wieder online sind.", "en") == "No connection - will send when you're back online.",
      "...and a German one in English (the row was written on a German phone)")
check(again("No connection - will send when you're back online.", "en") == "No connection - will send when you're back online.",
      "a sentence already in the language is unchanged")
check(again("Rejected by the server (invalid_field). Ask your admin.", "de") == "Vom Server abgelehnt (invalid_field). Bitte fragen Sie Ihre Verwaltung.",
      "a sentence with a code in it keeps the code")
check(again("Vom Server abgelehnt (http_418). Bitte fragen Sie Ihre Verwaltung.", "en") == "Rejected by the server (http_418). Ask your admin.",
      "...in both directions")
check(again("Shift at Haus A ended 14:00", "de") == "Schicht in 14:00 endete um Haus A",
      "a German template that reorders its arguments (%2$@ before %1$@) is rebuilt from the right captures")
check(again("Schicht in 14:00 endete um Haus A", "en") == "Shift at Haus A ended 14:00", "...and the other way round")
check(again("Musterhaus Wien 3", "de") == "Musterhaus Wien 3", "a building's name is not a catalogue sentence and is never touched")
check(again("Haus A in Wien", "en") == "Haus A in Wien",
      "a template too short to be a sentence (\"%@ in %@\") is not a pattern: a name must never be rewritten by it")
check(again("Cancel", "de") == "Abbrechen", "a one-word exact entry is found")
check(again("Abbrechen", "en") == "Abbrechen",
      "TWO keys with the same German text and different English ('Cancel' / 'Close') are ambiguous: the text is left as it is, never guessed")
check(again("", "de") == "", "the empty string stays empty")
check(again("Your session ended. Sign in again.", "de") == "Your session ended. Sign in again.",
      "a sentence the catalogue does not have is unchanged")

// ---------------------------------------------------------------------------------
// 7. The REAL catalogue, loaded the way the app loads it, in both directions
// ---------------------------------------------------------------------------------

if let data = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let strings = root["strings"] as? [String: Any] {
    var tables: [String: [String: String]] = ["de": [:], "en": [:]]
    for (key, value) in strings {
        let locales = (value as? [String: Any])?["localizations"] as? [String: Any]
        for language in ["de", "en"] {
            if let unit = (locales?[language] as? [String: Any])?["stringUnit"] as? [String: Any],
               let text = unit["value"] as? String { tables[language]![key] = text }
        }
    }
    let real = SentenceIndex(tables: tables)
    func germanOf(_ english: String) -> String { real.rerender(english, into: "de") }
    func englishOf(_ german: String) -> String { real.rerender(german, into: "en") }

    let sentence = "No connection - will send when you're back online."
    check(germanOf(sentence) != sentence && englishOf(germanOf(sentence)) == sentence,
          "the catalogue's own 'no connection' row sentence goes English -> German -> English")
    let rejected = "Rejected by the server (invalid_field). Ask your admin."
    check(germanOf(rejected).contains("invalid_field") && germanOf(rejected) != rejected && englishOf(germanOf(rejected)) == rejected,
          "...and the one with a server code in it keeps the code through the round trip")
    let notice = "Finished your open shift at Haus A and started at Haus B. Confirm when you actually left Haus A — it will not count until you do."
    check(germanOf(notice) != notice && germanOf(notice).contains("Haus A") && germanOf(notice).contains("Haus B")
          && englishOf(germanOf(notice)) == notice,
          "...and the building-switch notice with two names, one of them twice, survives a positional German template")
    check(real.rerender("Anna Rig", into: "de") == "Anna Rig" && real.rerender("Stiege 1", into: "en") == "Stiege 1",
          "a worker's or a building's name is never rewritten by the real catalogue")
    check(germanOf("Shift help") == "Hilfe zur Schicht" && englishOf("Hilfe zur Schicht") == "Shift help",
          "an entry with an explicit English value is found from either side")
} else {
    check(false, "Localizable.xcstrings is readable")
}

// ---------------------------------------------------------------------------------
// 8. THE BYPASS CHECK (decision-74 rule 6): nothing user-visible reaches the bundle on its own
// ---------------------------------------------------------------------------------

let sourceFiles = ((try? FileManager.default.contentsOfDirectory(atPath: "NFCTimeSheets")) ?? [])
    .filter { $0.hasSuffix(".swift") }.sorted()
check(sourceFiles.count > 40 && sourceFiles.contains("AppLanguage.swift"), "the source directory was found (\(sourceFiles.count) files)")

// A pattern, and what it would let through. DemoHooks.swift is DEBUG-only and its strings never ship
// (TASK-278): it is the one file the sweep leaves alone, and is named so.
let bypasses: [(pattern: String, why: String)] = [
    ("String(localized:", "`String(localized:)` resolves from the PROCESS's language and ignores a live switch - use AppLanguage.string(...)"),
    ("NSLocalizedString(", "NSLocalizedString is the same bypass - use AppLanguage.string(...)"),
    ("localizedString(forKey", "a bundle lookup by key is the same bypass - use AppLanguage.string(...)"),
    ("String.LocalizationValue", "a LocalizationValue is resolved by String(localized:), the same bypass"),
    ("LocalizedStringResource(", "build the resource through AppLanguage.string(\"...\"), which sets its locale"),
    ("Locale.current", "the phone's locale, not the app language's - take `\\.locale` from the environment"),
    ("Locale.autoupdatingCurrent", "the phone's locale, not the app language's"),
    ("Locale.preferredLanguages", "only AppLanguage reads the phone's languages"),
    ("Bundle.main.preferredLocalizations", "only AppLanguage decides the language"),
    ("\"AppleLanguages\"", "the OS key is AppLanguage.overrideKey, written by AppLanguage only (no second flag)"),
    ("AppleLanguages", "the OS key is AppLanguage.overrideKey, written by AppLanguage only (no second flag)"),
]
for file in sourceFiles where file != "AppLanguage.swift" && file != "DemoHooks.swift" {
    let text = code(source(file))
    for (pattern, why) in bypasses where text.contains(pattern) {
        check(false, "\(file) uses '\(pattern)': \(why)")
    }
}

// The only way a string is looked up is AppLanguage.string("literal"...): a first argument that is a literal
// is what the compiler's string extraction (and localisation-check) can see.
let callPattern = try! NSRegularExpression(pattern: #"AppLanguage\.string\(\s*[^"\s]"#)
for file in sourceFiles where file != "AppLanguage.swift" {
    let text = code(source(file))
    let hits = callPattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    check(hits == 0, "\(file) calls AppLanguage.string with something other than a string literal (\(hits)x): the extractor and localisation-check cannot see it")
}

// The language reaches the screens through the root environment and never by recreating the tree.
let app = code(source("NFCTimeSheetsApp.swift"))
check(app.contains(".appLanguage()"), "the app puts the language into the environment at the root")
let afterBanner = app.components(separatedBy: ".demoBanner()").last ?? ""
check(afterBanner.contains(".appLanguage()") && !afterBanner.contains(".environment(inbox)"),
      "...as the LAST modifier, so what is above it (sheets, alerts, the content) resolves in it")
let model = code(source("AppLanguageModel.swift"))
check(model.contains(".environment(\\.locale, model.locale)"), "the model's locale is THE \\.locale of the app")
for file in sourceFiles where file != "AppLanguageModel.swift" {
    let text = code(source(file))
    check(!text.contains(".id(AppLanguage") && !text.contains(".id(language") && !text.contains(".id(model.") && !text.contains(".id(locale"),
          "\(file) recreates a view tree on a language change: that would drop a material draft, an open sheet and a pushed screen (decision-74 rule 5)")
}

// The language control and the resolver touch no session, no shift, no draft and no queue (rule 5).
let resolver = code(source("AppLanguage.swift")) + code(source("AppLanguageModel.swift"))
for forbidden in ["Session", "ModelContext", "Shift", "MaterialStore", "signOut", "syncPending", "URLSession", "apiPost"] {
    check(!resolver.contains(forbidden), "AppLanguage / AppLanguageModel mention '\(forbidden)': switching language must touch nothing but the words")
}
check(code(source("AppLanguage.swift")).contains("import Foundation") && !code(source("AppLanguage.swift")).contains("import SwiftUI")
      && !code(source("AppLanguage.swift")).contains("import UIKit"), "AppLanguage.swift imports Foundation and nothing else (the check cats it in)")

// ---------------------------------------------------------------------------------
// 9. A stored sentence is never drawn as it is
// ---------------------------------------------------------------------------------
//
// Every place that draws a sentence a row, a state or an earlier event stored must say it again
// through rerender. A file listed here that loses its call is a screen that silently keeps the old
// language after a switch ("it does not silently stay in the old language", decision-74 Consequences).

let rerenderSites: [(file: String, needles: [String])] = [
    ("ContentView.swift", ["AppLanguage.rerender(reason, locale: locale)", "AppLanguage.rerender(message, locale: locale)",
                           "AppLanguage.rerender(scanError ?? \"\", locale: locale)", "AppLanguage.rerender(manualError, locale: locale)",
                           "AppLanguage.rerender(err, locale: locale)", "AppLanguage.rerender(error, locale: locale)"]),
    ("PendingNoticeView.swift", ["AppLanguage.rerender(sentence, locale: locale)"]),
    ("ShiftScreen.swift", ["AppLanguage.rerender(text, locale: locale)"]),
    ("ShiftReceiptView.swift", ["AppLanguage.rerender(sentence, locale: locale)"]),
    ("MaterialsView.swift", ["AppLanguage.rerender(error, locale: locale)"]),
    ("CodeSignInSection.swift", ["AppLanguage.rerender(phoneErrorMessage, locale: locale)",
                                 "AppLanguage.rerender(codeErrorMessage, locale: locale)"]),
    ("OperatorHomeScreen.swift", ["AppLanguage.rerender(reason, locale: locale)"]),
    ("ShiftProofSheet.swift", ["AppLanguage.rerender(error, locale: locale)"]),
    ("VerifyZoneScreen.swift", ["AppLanguage.rerender(message, locale: locale)", "AppLanguage.rerender(createdNotice, locale: locale)"]),
    ("WriteTagScreen.swift", ["AppLanguage.rerender(message, locale: locale)"]),
]
for (file, needles) in rerenderSites {
    let text = code(source(file))
    for needle in needles {
        check(text.contains(needle), "\(file) draws a stored sentence without saying it again in the language in force (missing \(needle))")
    }
}

// A view that resolves a string in code reads the language from its own environment, so a switch
// re-evaluates it. The pin is coarse on purpose: a file that calls `locale: locale` declares the property.
for file in sourceFiles where file != "AppLanguage.swift" && file != "AppLanguageModel.swift" {
    let text = code(source(file))
    if text.contains("locale: locale)") && file != "ViennaTime.swift" {
        check(text.contains("@Environment(\\.locale) private var locale"),
              "\(file) passes `locale: locale` but declares no `@Environment(\\.locale) private var locale`")
    }
}

// The reminders' wording is fixed when SCHEDULED, in the language in force at that arm (rule 4).
let center = code(source("ShiftSignalCenter.swift"))
check(center.contains("let language = AppLanguage.effective") && count(center, "language: language") == 6,
      "every reminder string (a title and a body for each of the three kinds) is built in the language in force at arm time, not the process's")

// ---------------------------------------------------------------------------------
// 10. THE CONTROL (TASK-365.15, decision-74 rules 1, 2, 5)
// ---------------------------------------------------------------------------------

let picker = code(source("LanguagePicker.swift"))
let content = code(source("ContentView.swift"))
check(!picker.isEmpty, "LanguagePicker.swift exists: ONE view for both places, so they can never disagree")
// Three options, in Android's order, from the resolver's own list - and nothing but the model is called by a tap.
check(picker.contains("ForEach(AppLanguage.options, id: \\.self)") && picker.contains("model.select(value)")
      && count(picker, "model.select(") == 1,
      "the options are AppLanguage.options (de, en, follow the phone) and a tap calls model.select(value) and nothing else")
check(picker.contains("case \"de\": return Text(\"Deutsch\")") && picker.contains("case \"en\": return Text(\"English\")")
      && picker.contains("default: return Text(\"Use phone language\")") && picker.contains("Text(\"Language\")"),
      "the words are literals (LocalizedStringKey): Deutsch, English, Use phone language, under the title Language")
for forbidden in ["Session", "ModelContext", "@Query", "Shift", "MaterialStore", "signOut", "syncPending", "URLSession", "apiPost",
                  "ShiftSignalCenter", "TapInbox", "exit(", "UserDefaults"] {
    check(!picker.contains(forbidden), "LanguagePicker mentions '\(forbidden)': a tap on it changes the words and nothing else (decision-74 rule 5)")
}
check(picker.contains(".accessibilityAddTraits(selected ? [.isSelected] : [])") && picker.contains(".accessibilityIdentifier(identifier(value))"),
      "the selected option is exposed as selected (Android: Role.RadioButton), and each option has an identifier")
check(picker.contains("typeSize.isAccessibilitySize") && picker.contains("minHeight: WorkerStyle.quietButtonMinHeight")
      && picker.contains("WorkerStyle.inverse") && picker.contains("WorkerStyle.onInverse") && picker.contains("WorkerStyle.soft"),
      "it is drawn in the worker tokens (inverse fill on a soft track, 48 pt minimum) and stacks at the accessibility sizes")
// Placement: the signed-out screen under the brand block (before everything else), and More after the identity card.
let signedOut = between2(content, "struct SignInView: View {", "struct LogView: View {")
check(count(signedOut, "LanguagePicker()") == 1, "the signed-out screen has the picker once")
check(inOrder(signedOut, ["Image(\"BrandMark\")", "LanguagePicker()", "DeliveryStatusRows(rows: deliveryRows, signedOut: true)",
                          "CodeSignInSection(role: .worker"]),
      "...under the brand block and before the delivery rows and the sign-in form (Android SignInScreen)")
let settingsView = between2(content, "struct SettingsView: View {", "private func cardRow(")
check(inOrder(settingsView, ["identityCard", "LanguagePicker()", ".workerCard()", "Button(\"Sign out\")"]),
      "More: the language card follows the identity card and comes before Sign out")
// The OPERATOR screens are not a second place: they take the language from the same environment.
check(count(content, "LanguagePicker()") == 2, "exactly two places carry the control: the signed-out screen and More")

// Android's words, verbatim, in both languages (TASK-365.15 AC1): title, Deutsch, English, Wie am Telefon / Use phone language.
func androidWord(_ name: String, en: Bool) -> String? {
    let file = en ? "values-en" : "values"
    guard let xml = try? String(contentsOfFile: "../android/app/src/main/res/\(file)/strings.xml", encoding: .utf8) else { return nil }
    let open = "<string name=\"\(name)\">"
    guard let start = xml.range(of: open), let end = xml.range(of: "</string>", range: start.upperBound..<xml.endIndex) else { return nil }
    return String(xml[start.upperBound..<end.lowerBound])
}
if let data = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let strings = root["strings"] as? [String: Any] {
    func word(_ key: String, _ language: String) -> String? {
        let unit = (((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }
    for (key, android) in [("Language", "language_title"), ("Deutsch", "language_de"), ("English", "language_en"),
                           ("Use phone language", "language_system")] {
        check(word(key, "de") != nil && word(key, "de") == androidWord(android, en: false),
              "'\(key)' has Android's German (\(android)) verbatim: '\(androidWord(android, en: false) ?? "?")', got '\(word(key, "de") ?? "nil")'")
        check(word(key, "en") != nil && word(key, "en") == androidWord(android, en: true),
              "'\(key)' has an explicit English entry that is Android's (\(android)): '\(androidWord(android, en: true) ?? "?")', got '\(word(key, "en") ?? "nil")'")
    }
}

func between2(_ s: String, _ from: String, _ to: String) -> String {
    let parts = s.components(separatedBy: from)
    guard parts.count > 1 else { return "" }
    return parts[1].components(separatedBy: to)[0]
}
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}

if failed { exit(1) }
print("app-language-check: OK")
