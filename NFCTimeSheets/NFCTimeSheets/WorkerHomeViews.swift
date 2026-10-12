//
//  WorkerHomeViews.swift
//  NFCTimeSheets
//
//  THE IDLE SCREEN'S OWN PIECES (TASK-365.10 / iOS B2). Ported from android/.../ui/WorkerHomeCards.kt
//  `WorkerDayHeading` at 60f6886. The start block and the receipt stay where they were - inline in
//  LogView.idleList and in ShiftReceiptView - because the checks that pin the receipt-or-start rule
//  read them there; this file holds what is NEW and has no behaviour to pin.
//
//  DISPLAY ONLY. No store, no context, no API, no tap: a date and a title.
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
