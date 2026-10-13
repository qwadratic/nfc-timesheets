//
//  AppLanguage.swift
//  NFCTimeSheets
//
//  THE ONE RESOLVER (decision-74 rule 6, TASK-365.14). Every user-visible string, date and number
//  in this app is in the language this file says, and nothing else decides it: a `String(localized:)`
//  that reaches the main bundle on its own is a build-time failure of checks/app-language-check.swift,
//  the same way localisation-check fails on a missing German entry.
//
//  THREE VALUES, and only these: "" (follow the phone, the default), "de", "en"  (Android's
//  AppLanguage.kt `require(language in listOf("", "de", "en"))`).
//
//  ONE SOURCE OF TRUTH, SHARED WITH THE OS (decision-74 rule 3). The choice is the app's per-app
//  language value, `AppleLanguages` in the app's OWN defaults domain: the key iOS Settings > this app >
//  Language writes, and the key iOS reads at the next launch to pick the bundle's language for
//  everything this file cannot reach (system sheets, permission prompts). There is no second flag
//  beside it. "Follow the phone" REMOVES the key; it is never a third stored state.
//
//    - the selection is read from the app domain ONLY, never from `UserDefaults.array(forKey:)`:
//      that falls through to the global domain and would answer the phone's own list, so "follow
//      the phone" would look like a choice;
//    - an `-AppleLanguages (xx)` launch argument lives in the ARGUMENT domain and is therefore not a
//      selection; it still counts as "the phone says xx" (Locale.preferredLanguages), which is what
//      the rig's UI tests rely on.
//
//  WHY A RESOLVER ON TOP OF THE OS VALUE (decision-74 "Consequences"): iOS reads the per-app value
//  once per launch. Setting it in the running process changes `Locale.preferredLanguages` at once
//  (measured, iOS 26.5 Simulator) but not what `Bundle.main` hands to `String(localized:)`. So the
//  live switch needs the language to be an INPUT: SwiftUI gets it as `\.locale` from the root, and a
//  string built in code asks this file, which sets the `LocalizedStringResource`'s own locale before
//  resolving it (`String(localized:bundle:locale:)` ignores the locale for choosing the lproj; the
//  resource form does not - measured the same way).
//
//  WHAT CANNOT FOLLOW A LIVE SWITCH, and says so here (decision-74 "Consequences"): text the OS draws
//  itself from the app's bundle at LAUNCH - the permission prompts (InfoPlist.strings: camera, location,
//  NFC), the Core NFC reader sheet's chrome, the system alert buttons' own words. They are in the language
//  the process started in and take the new one at the next launch, from the same per-app value. Nothing
//  the app draws is in that class: every screen, sentence, date, number and reminder follows at once.
//
//  FOUNDATION ONLY, like TagLink.swift and ShiftSignal.swift: the check cats this file in and runs it
//  on a Mac with a throwaway bundle of de.lproj / en.lproj, a fake store and no Xcode.
//
//  WHAT IS DELIBERATELY NOT HERE
//    - the "this week" boundary (decision-74 rule 8): a total must not change because the UI
//      language did, so History keeps `Calendar.current`.
//    - what a phone in NEITHER language gets (TASK-327, the owner's developmentRegion edit): the
//      fallback is the bundle's own development language (`Bundle.main.developmentLocalization`,
//      "en" today), read, not hard-coded, so that edit moves it without touching this file.
//

import Foundation

enum AppLanguage {

    // MARK: - The value set

    /// What the app has translations for. Order is irrelevant; membership is the rule.
    static let supported: [String] = ["de", "en"]

    /// The stored value and the three radio options, in the order the picker shows them
    /// (Android LanguagePicker: de, en, system).
    static let options: [String] = ["de", "en", ""]

    /// The OS's own key. Written to the app's defaults domain; removed for "follow the phone".
    static let overrideKey = "AppleLanguages"

    /// Posted (main thread, after the value is stored) when the effective selection changed.
    /// Things that cannot observe a SwiftUI environment - the reminder ladder - hang off this.
    static let didChange = Notification.Name("io.github.qwadratic.NFCTimeSheets.appLanguageDidChange")

    static func isValid(_ selection: String) -> Bool { selection.isEmpty || supported.contains(selection) }

    // MARK: - Pure rules (run for real by the check)

    /// "de-AT" / "de_AT" / "DE" -> "de".
    static func primary(of tag: String) -> String {
        let end = tag.firstIndex(where: { $0 == "-" || $0 == "_" }) ?? tag.endIndex
        return String(tag[..<end]).lowercased()
    }

    /// The selection the OS-owned per-app value stands for: "" when there is none, or when its first
    /// entry is not a language this app has (nobody picked that here).
    static func selection(fromStored stored: [String]?) -> String {
        guard let first = stored?.first else { return "" }
        let language = primary(of: first)
        return supported.contains(language) ? language : ""
    }

    /// The language everything is in. A choice wins outright. "Follow the phone" is the first of the
    /// phone's languages the app has, exactly how iOS matches a bundle; a phone with none of ours gets
    /// the bundle's development language (TASK-327's, "en" today).
    static func effective(selection: String, preferred: [String], developmentLanguage: String?) -> String {
        if supported.contains(selection) { return selection }
        for tag in preferred {
            let language = primary(of: tag)
            if supported.contains(language) { return language }
        }
        let fallback = developmentLanguage.map(primary(of:)) ?? ""
        return supported.contains(fallback) ? fallback : "en"
    }

    /// The Locale dates, times and numbers are formatted with.
    ///
    /// "Follow the phone" on a phone whose own language is the effective one IS the phone's locale,
    /// region and all (24 h clock, "14.07.2026"): exactly what iOS did before this control existed.
    /// Anything else is the BARE language - Android's `Locale.forLanguageTag("de")` - so an explicit
    /// choice gives "7,5 Std." / "7.5 h" and not the phone's region's separators.
    static func locale(selection: String, effective: String, system: Locale) -> Locale {
        if selection.isEmpty, primary(of: system.identifier) == effective { return system }
        return Locale(identifier: effective)
    }

    // MARK: - The stored value (the OS's), behind a seam

    /// Where the per-app value lives. `standard` is the real defaults domain; the check hands in a
    /// dictionary-backed one so a Mac script never touches its own preferences.
    struct Store {
        var read: () -> [String]?
        var write: ([String]?) -> Void

        static let standard = Store(
            read: {
                let domain = Bundle.main.bundleIdentifier ?? ""
                return UserDefaults.standard.persistentDomain(forName: domain)?[AppLanguage.overrideKey] as? [String]
            },
            write: { value in
                if let value { UserDefaults.standard.set(value, forKey: AppLanguage.overrideKey) }
                else { UserDefaults.standard.removeObject(forKey: AppLanguage.overrideKey) }
            })
    }

    // MARK: - The process-wide state

    /// What the phone says it speaks, injectable so the check can put a French phone in front of it.
    private struct World {
        var store: Store = .standard
        var preferred: () -> [String] = { Locale.preferredLanguages }
        var system: () -> Locale = { Locale.current }
        var developmentLanguage: () -> String? = { Bundle.main.developmentLocalization }
        var selection: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var world = World()

    private static func locked<T>(_ body: (inout World) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&world)
    }

    /// The stored selection: "" | "de" | "en". Read once and kept; `set` and `refresh` move it.
    static var selection: String {
        locked { world in
            if let known = world.selection { return known }
            let value = selection(fromStored: world.store.read())
            world.selection = value
            return value
        }
    }

    /// The language in force right now: "de" or "en".
    static var effective: String {
        let chosen = selection
        return locked { world in
            effective(selection: chosen, preferred: world.preferred(), developmentLanguage: world.developmentLanguage())
        }
    }

    /// The Locale in force right now.
    static var locale: Locale {
        let chosen = selection
        let language = effective
        return locked { world in locale(selection: chosen, effective: language, system: world.system()) }
    }

    /// Stores a choice. Only "", "de", "en" are accepted - anything else is refused and writes nothing.
    /// Posts `didChange` when the EFFECTIVE selection moved; never touches a session, a shift, a
    /// draft or the pending queue (decision-74 rule 5): it writes one defaults key and tells whoever
    /// asked to be told.
    @discardableResult
    static func set(_ newValue: String) -> Bool {
        guard isValid(newValue) else { return false }
        let before = selection
        locked { world in
            world.store.write(newValue.isEmpty ? nil : [newValue])
            world.selection = newValue
        }
        if before != newValue { notify() }
        return true
    }

    /// Reads the stored value again (a foreground return: another process may have written it).
    static func refresh() {
        let before = selection
        let after: String = locked { world in
            let value = selection(fromStored: world.store.read())
            world.selection = value
            return value
        }
        if before != after { notify() }
    }

    private static func notify() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChange, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }

    /// Check seam: a fake store, a fake phone, and a way back.
    static func useForTesting(store: Store, preferred: [String], system: Locale, developmentLanguage: String?) {
        locked { world in
            world.store = store
            world.preferred = { preferred }
            world.system = { system }
            world.developmentLanguage = { developmentLanguage }
            world.selection = nil
        }
    }

    // MARK: - Strings

    /// A string from the catalogue, in the language in force. Used where there is no SwiftUI
    /// environment to ask (a model, a notification, a stored message). A VIEW passes its own
    /// `locale:` instead, so it is re-evaluated when the language changes.
    static func string(_ resource: LocalizedStringResource) -> String {
        string(resource, language: effective)
    }

    /// The same, in the language of `locale` (a view's `\.locale`). A locale of some other language is
    /// read as the language in force: this app has two.
    static func string(_ resource: LocalizedStringResource, locale: Locale) -> String {
        string(resource, language: language(of: locale))
    }

    /// `language` must be one of `supported`; anything else is read as the language in force.
    static func string(_ resource: LocalizedStringResource, language: String) -> String {
        var resource = resource
        let chosen = supported.contains(language) ? language : effective
        resource.locale = Locale(identifier: chosen)
        return String(localized: resource)
    }

    /// The supported language a Locale stands for; the language in force when it is neither.
    static func language(of locale: Locale) -> String {
        let language = primary(of: locale.identifier)
        return supported.contains(language) ? language : effective
    }

    // MARK: - Numbers and dates (decision-74 "Consequences": format styles, never a literal unit)

    /// "7,5 Std." / "7.5 h": one decimal, the language's separator, the language's unit word
    /// (the catalogue key is "%@ h", German "%@ Std."). Android: `hours_format`.
    static func hours(_ value: Double, locale: Locale) -> String {
        let number = value.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return string("\(number) h", locale: locale)
    }

    /// A date and/or time in `locale` - `Date.formatted(date:time:)`, which takes no locale and reads the
    /// phone's. The zone is the phone's, as before; the Vienna-pinned plan lines go through ViennaTime.
    static func formatted(_ instant: Date,
                          date: Date.FormatStyle.DateStyle = .omitted,
                          time: Date.FormatStyle.TimeStyle = .omitted,
                          locale: Locale) -> String {
        instant.formatted(Date.FormatStyle(date: date, time: time, locale: locale))
    }

    // MARK: - A sentence that was said earlier, said again in the language in force now

    /// A stored sentence is a catalogue VALUE in whichever language was in force when it was made: a
    /// row's `syncError`, a message in a view's @State, the sign-in screen's refusal. After a switch
    /// it would keep that language (decision-74: "it does not silently stay in the old language").
    /// This finds the catalogue KEY the text came from - by the exact value, or by the value's
    /// pattern for a sentence with a name or a code in it - and says it again in `language`.
    ///
    /// Text that is not a catalogue sentence (a building's name, a code, free text, a sentence a
    /// build before this one stored in a language it no longer has) comes back UNCHANGED. It never
    /// guesses: more than one key with different answers is "unchanged" too.
    static func rerender(_ text: String, locale: Locale) -> String {
        rerender(text, language: language(of: locale))
    }

    static func rerender(_ text: String) -> String {
        rerender(text, language: effective)
    }

    static func rerender(_ text: String, language: String) -> String {
        guard !text.isEmpty else { return text }
        return catalogueIndex().rerender(text, into: language)
    }

    nonisolated(unsafe) private static var indexCache: SentenceIndex?
    nonisolated(unsafe) private static var indexBundle: Bundle?

    /// Built from the main bundle's compiled tables on first use. A check can swap the bundle.
    private static func catalogueIndex() -> SentenceIndex {
        lock.lock()
        defer { lock.unlock() }
        if let indexCache { return indexCache }
        let built = SentenceIndex(tables: SentenceIndex.loadTables(bundle: indexBundle ?? .main, languages: supported))
        indexCache = built
        return built
    }

    static func useCatalogueForTesting(bundle: Bundle?) {
        lock.lock()
        defer { lock.unlock() }
        indexBundle = bundle
        indexCache = nil
    }
}

// MARK: - The index behind rerender

/// Every sentence the catalogue can produce, in every language, searchable by what it SAYS.
struct SentenceIndex {
    /// language -> key -> value. A key a table does not carry is its own value (the source language's
    /// entries are not written out when they equal the key).
    let tables: [String: [String: String]]

    private let exact: [String: [String]]
    private let patterns: [Pattern]

    private struct Pattern {
        let key: String
        let regex: NSRegularExpression
        /// For capture group i, which argument of the KEY it is.
        let arguments: [Int]
        let literalLength: Int
    }

    /// One parsed `%@` / `%lld` / `%1$@` template.
    private struct Template {
        enum Piece { case literal(String), argument(Int) }
        let pieces: [Piece]
        var hasArguments: Bool { pieces.contains { if case .argument = $0 { return true } else { return false } } }
        var literalLength: Int { pieces.reduce(0) { if case .literal(let s) = $1 { return $0 + s.count } else { return $0 } } }
    }

    private static let placeholder = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(?:lld|ld|d|@|s|f)|%%"#)

    private static func parse(_ template: String) -> Template {
        var pieces: [Template.Piece] = []
        var cursor = template.startIndex
        var sequential = 0
        let whole = NSRange(template.startIndex..., in: template)
        for match in placeholder.matches(in: template, range: whole) {
            let range = Range(match.range, in: template)!
            if cursor < range.lowerBound { pieces.append(.literal(String(template[cursor..<range.lowerBound]))) }
            if template[range] == "%%" {
                pieces.append(.literal("%"))
            } else if match.range(at: 1).location != NSNotFound,
                      let position = Int(template[Range(match.range(at: 1), in: template)!]) {
                pieces.append(.argument(position - 1))
            } else {
                pieces.append(.argument(sequential))
                sequential += 1
            }
            cursor = range.upperBound
        }
        if cursor < template.endIndex { pieces.append(.literal(String(template[cursor...]))) }
        return Template(pieces: pieces)
    }

    /// A pattern shorter than this in plain characters would match too much ("%@ at %@").
    private static let minimumLiteralLength = 12

    init(tables: [String: [String: String]]) {
        self.tables = tables
        var keys = Set<String>()
        for table in tables.values { keys.formUnion(table.keys) }

        var exact: [String: [String]] = [:]
        var patterns: [Pattern] = []
        for key in keys.sorted() {
            let keyTemplate = Self.parse(key)
            for language in tables.keys.sorted() {
                let value = tables[language]?[key] ?? key
                if !keyTemplate.hasArguments {
                    exact[value, default: []].append(key)
                    continue
                }
                let template = Self.parse(value)
                guard template.literalLength >= Self.minimumLiteralLength else { continue }
                var source = "^"
                var arguments: [Int] = []
                for piece in template.pieces {
                    switch piece {
                    case .literal(let text): source += NSRegularExpression.escapedPattern(for: text)
                    case .argument(let index):
                        source += "(.+?)"
                        arguments.append(index)
                    }
                }
                source += "$"
                if let regex = try? NSRegularExpression(pattern: source, options: [.dotMatchesLineSeparators]) {
                    patterns.append(Pattern(key: key, regex: regex, arguments: arguments,
                                            literalLength: template.literalLength))
                }
            }
        }
        // A key's value is the same in two languages for "OK" - one entry is enough.
        self.exact = exact.mapValues { Array(Set($0)).sorted() }
        self.patterns = patterns
    }

    func rerender(_ text: String, into language: String) -> String {
        if let keys = exact[text] {
            let answers = Set(keys.map { say(key: $0, arguments: [:], in: language) })
            return answers.count == 1 ? answers.first! : text
        }
        var best: (length: Int, answers: Set<String>) = (0, [])
        let whole = NSRange(text.startIndex..., in: text)
        for pattern in patterns where pattern.literalLength >= best.length {
            guard let match = pattern.regex.firstMatch(in: text, range: whole),
                  match.numberOfRanges == pattern.arguments.count + 1 else { continue }
            var captured: [Int: String] = [:]
            for (group, argument) in pattern.arguments.enumerated() {
                guard let range = Range(match.range(at: group + 1), in: text) else { continue }
                captured[argument] = String(text[range])
            }
            let answer = say(key: pattern.key, arguments: captured, in: language)
            if pattern.literalLength > best.length { best = (pattern.literalLength, [answer]) }
            else { best.answers.insert(answer) }
        }
        return best.answers.count == 1 ? best.answers.first! : text
    }

    private func say(key: String, arguments: [Int: String], in language: String) -> String {
        let value = tables[language]?[key] ?? key
        let template = Self.parse(value)
        var out = ""
        for piece in template.pieces {
            switch piece {
            case .literal(let text): out += text
            case .argument(let index): out += arguments[index] ?? ""
            }
        }
        return out
    }

    /// The compiled `Localizable.strings` of each language lproj in `bundle`.
    static func loadTables(bundle: Bundle, languages: [String]) -> [String: [String: String]] {
        var tables: [String: [String: String]] = [:]
        for language in languages {
            guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil,
                                         forLocalization: language),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
            tables[language] = table
        }
        return tables
    }
}
