//
//  WorkerHomeViews.swift
//  NFCTimeSheets
//
//  THE WORKER SCREENS' OWN PIECES (TASK-365.10 / iOS B2, TASK-365.13 / iOS B5). Ported from
//  android/.../ui/WorkerHomeCards.kt `WorkerDayHeading` and `WorkerIdentity` at 60f6886. The start block and the receipt stay where they were - inline in
//  LogView.idleList and in ShiftReceiptView - because the checks that pin the receipt-or-start rule
//  read them there; this file holds what is NEW and has no behaviour to pin.
//
//  DISPLAY ONLY. No store, no context, no API, no tap: a date and a title, and a name in a circle.
//

import SwiftUI

/// Today's date and "Your working day", at the top of the idle screen.
///
/// The date line is Android's `EEEE · d MMMM` in the app's locale ("Montag · 12 Oktober",
/// "Monday · 12 October") and is READ AGAIN EACH MINUTE (a TimelineView on the minute, so a phone
/// left on the idle screen across midnight shows the new day - Android's produceState loop). The
/// title is a VoiceOver header; the date is its own line above it, spoken before the title like
/// Android's.
struct WorkerDayHeading: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.everyMinute) { context in
                Text(verbatim: Self.dateLine(context.date, locale: locale))
                    .font(WorkerStyle.Typeface.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Your working day")
                .font(WorkerStyle.Typeface.title)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `EEEE · d MMMM` - the weekday, a middle dot, the day and the month name, as Android prints it.
    /// A DATA string (built from the clock and the locale), so it is verbatim and never a catalogue key.
    static func dateLine(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE · d MMMM"
        return formatter.string(from: date)
    }
}

/// The head of More's identity card: the worker's initials in a soft circle, then the name
/// (Android `WorkerIdentity`: a 50 dp circle with the first letters of the first two name parts,
/// hidden from TalkBack, beside the name in titleLarge).
///
/// The circle is DECORATION: hidden from VoiceOver, because the name beside it says everything it
/// says. The name keeps its spoken label "Signed in as <name>" - the sentence the old "Signed in as"
/// section header used to give it, now that the printed label is gone (Android dropped
/// "Angemeldet als:" too). The circle follows Dynamic Type so two letters never clip.
struct WorkerIdentity: View {
    let name: String

    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 50

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: WorkerInitials.of(name))
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: diameter, height: diameter)
                .background(WorkerStyle.soft, in: Circle())
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(WorkerStyle.Typeface.lead)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Signed in as \(name)")
        }
    }
}
