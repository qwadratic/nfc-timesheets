//
//  VersionGateRow.swift
//  NFCTimeSheets
//
//  THE VERSION LINE, AND THE ONLY DOOR TO THE OPERATOR TOOLS (TASK-365.13 / iOS B5, ported from
//  android/.../ui/TimeSheetApp.kt `app_version_line` rows at 60f6886).
//
//  decision-45 makes an operator a separate identity and decision-54 gates REACHING the operator
//  screens, so neither the signed-out screen nor More prints a row that says "Write or test tags"
//  any more: the version line (decision-52's wording, "Installed: 1.0 (11)") is a button, and the
//  fifth tap (VersionTapGate) opens OperatorHomeScreen - which is still the gate: no operator
//  cookie shows the shared code / SMS form, a cookie shows the two actions.
//
//  EACH SCREEN OWNS ITS COUNTER: this row keeps its own @State, so the sign-in screen and More
//  count separately and nothing is persisted or sent. It shows nothing on taps one to four (no
//  hint, no haptic): the gesture is for staff who were told.
//
//  The CALLER owns what "open" means (a `navigationDestination(isPresented:)` on its own stack).
//

import SwiftUI

struct VersionGateRow: View {
    /// Flipped to true by the fifth tap; the caller's `navigationDestination(isPresented:)` reads it.
    @Binding var openOperator: Bool
    /// This screen's own count (Android: a per-screen rememberSaveable).
    @State private var tapCount = 0

    /// The native fields Xcode writes into the built Info.plist from MARKETING_VERSION /
    /// CURRENT_PROJECT_VERSION - no build-setting edit needed or made (decision-52).
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        Button {
            let result = VersionTapGate.advance(tapCount)
            tapCount = result.tapCount
            if result.openOperator { openOperator = true }
        } label: {
            Text("Installed: \(Self.appVersion) (\(Self.appBuild))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                // A real target, not a line of footnote text: at least 48 pt tall and the whole width.
                .frame(maxWidth: .infinity, minHeight: WorkerStyle.quietButtonMinHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("version-line")
    }
}
