//
//  LanguagePicker.swift
//  NFCTimeSheets
//
//  THE LANGUAGE CONTROL (decision-74, TASK-365.15 / iOS E2). Ported from android/.../ui/LanguagePicker.kt
//  at 60f6886: a title, then three options in one row - Deutsch, English, "Wie am Telefon" / "Use phone
//  language" - exactly one of them selected, the chosen one filled with the INVERSE pair (Android:
//  `inverseSurface` / `inverseOnSurface` on a `surfaceContainerHigh` track), 48 pt tall at least.
//
//  Two places, both Android's: the signed-out screen under the brand block, and its own card in More
//  after the identity card. Same view, so the two can never disagree about order, copy or the value.
//
//  WHAT A TAP DOES: `AppLanguageModel.select` and nothing else. It writes the OS's per-app language
//  value (or removes it, for "follow the phone"), and SwiftUI re-resolves every string in the new
//  language because the root puts it into the environment. It is not in the tap path, it does not sign
//  anybody out, it does not touch a running shift, a material draft, the pending queue or a sheet that
//  is open (decision-74 rule 5; checks/app-language-check.swift reads this file for exactly that).
//
//  THE OPTION NAMES are the languages' own words and are the same in both languages ("Deutsch",
//  "English") - the one thing a worker locked in the wrong language can still read. Only the title and
//  the third option change with the language in force.
//
//  AT THE LARGEST TEXT SIZES the row would clip "Use phone language", so the three options stack: one
//  per line, full width, same fill rule.
//

import SwiftUI

struct LanguagePicker: View {
    @Environment(AppLanguageModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Android: labelLarge. A heading for VoiceOver, so the group is found from the rotor.
            Text("Language")
                .font(WorkerStyle.Typeface.label)
                .accessibilityAddTraits(.isHeader)
            options
                .padding(4)
                .background(WorkerStyle.soft, in: RoundedRectangle(cornerRadius: WorkerStyle.buttonRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One group, so VoiceOver reads "Language" once and then each option with its selected state.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("language-picker")
    }

    @ViewBuilder private var options: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 4) { segments }
        } else {
            // `fixedSize(vertical:)` + `maxHeight: .infinity` in each segment: one option wrapping to two
            // lines makes all three that tall, instead of one tall and two short.
            HStack(spacing: 4) { segments }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segments: some View {
        ForEach(AppLanguage.options, id: \.self) { value in
            segment(value)
        }
    }

    /// The label is a literal per option - a LocalizedStringKey - never a ternary of strings (TASK-298).
    private func label(_ value: String) -> Text {
        switch value {
        case "de": return Text("Deutsch")
        case "en": return Text("English")
        default: return Text("Use phone language")
        }
    }

    private func identifier(_ value: String) -> String {
        switch value {
        case "de": return "language-de"
        case "en": return "language-en"
        default: return "language-system"
        }
    }

    private func segment(_ value: String) -> some View {
        let selected = model.selection == value
        return Button {
            model.select(value)
        } label: {
            label(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? WorkerStyle.onInverse : Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: WorkerStyle.quietButtonMinHeight, maxHeight: .infinity)
                .background(selected ? WorkerStyle.inverse : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier(value))
    }
}
