//
//  AppLanguageModel.swift
//  NFCTimeSheets
//
//  THE SWIFTUI HALF OF THE LANGUAGE CONTROL (decision-74, TASK-365.14). AppLanguage.swift is the
//  resolver and is Foundation-only; this is the observable value the views read and the one
//  modifier that puts the language into the environment.
//
//  WHAT THE ENVIRONMENT DOES. `.environment(\.locale, ...)` at the root is what makes every
//  Text, Label, Button, navigation title, alert and accessibility label built from a literal resolve its
//  catalogue key in the language in force - live, in the running process - and what every view that
//  reads `@Environment(\.locale)` is invalidated by. It is NOT `.id(...)`: recreating the tree on a
//  switch would drop a half-typed material request, an open sheet and the pushed History, and the
//  rule (decision-74 rule 5) is that switching touches nothing but the words.
//

import SwiftUI

/// The language value the views observe. A thin shell: the truth is `AppLanguage.selection`, which is
/// the OS-owned per-app value.
@MainActor
@Observable
final class AppLanguageModel {
    static let shared = AppLanguageModel()

    /// "" | "de" | "en" - what is stored (the OS's per-app value).
    private(set) var selection: String = AppLanguage.selection

    /// The Locale in force. Reads `selection` first, so an observer is told when it changes.
    var locale: Locale {
        _ = selection
        return AppLanguage.locale
    }

    /// The language in force ("de" | "en").
    var effective: String {
        _ = selection
        return AppLanguage.effective
    }

    /// Stores a choice. Never touches a session, a shift, a draft or the queue (decision-74 rule 5).
    func select(_ value: String) {
        guard AppLanguage.set(value) else { return }
        selection = AppLanguage.selection
    }

    /// Reads the stored value again: a return to the foreground after the OS Settings were open.
    func refresh() {
        AppLanguage.refresh()
        if selection != AppLanguage.selection { selection = AppLanguage.selection }
    }
}

/// The root modifier: the language in the environment, and a re-read on every return to the
/// foreground. Applied ONCE, to ContentView, in NFCTimeSheetsApp.
struct AppLanguageEnvironment: ViewModifier {
    @State private var model = AppLanguageModel.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.locale, model.locale)
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refresh() }
            }
    }
}

extension View {
    /// Puts the app language (decision-74) into this view's environment. The root only.
    func appLanguage() -> some View { modifier(AppLanguageEnvironment()) }
}
