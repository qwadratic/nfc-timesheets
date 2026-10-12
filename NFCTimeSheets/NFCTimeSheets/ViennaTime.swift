//
//  ViennaTime.swift
//  NFCTimeSheets
//
//  EVERY DATE AND TIME A WORKER IS TOLD ABOUT THE PLAN IS VIENNA TIME, whatever zone the phone
//  is set to. The plan is made on the admin week board, which is zone-locked to Europe/Vienna
//  (web/lib/shifts.ts BUSINESS_TIME_ZONE), and the building it names is in Vienna: "08:00" on
//  the board has to read "08:00" on a phone that is on a Spanish holiday, on a work phone
//  nobody switched out of UTC, and across the two nights a year the clocks change. Android
//  pins the same zone (TimeSheetApp.kt viennaDate / viennaTime, TASK-189).
//
//  The zone is passed to the format style EXPLICITLY. `Date.formatted(date:time:)` reads the
//  phone's zone, which is only right on a phone whose zone happens to already be Vienna - no
//  guarantee at all - and `Calendar.current` would answer "is this the same day?" in that zone
//  too. checks/schedule-check.swift runs both from fixed instants with the device zone set to
//  Los Angeles, Auckland and UTC.
//
//  THE LOCALE IS ALWAYS PASSED IN, never defaulted (TASK-365.14, decision-74): it is the app
//  language's (`\.locale` of the view that draws the line, which the language control sets),
//  and a `Locale.current` default here is exactly the kind of bypass that would keep a plan
//  line in the phone's language after the worker chose the other one. Date style is MEDIUM and
//  time style SHORT, the same two Android uses (FormatStyle.MEDIUM / SHORT), through
//  DateFormatter and not Date.FormatStyle: the latter's `.shortened` answers "8:00" where the
//  locale's own pattern - and Android - say "08:00" (measured, de_AT and en_GB), and the
//  worker reads the SAME assignment on the admin board and on the other phone. (The locale
//  IS set on that formatter - a fixed-locale formatter is the other thing the language check bans.)
//
//  Foundation-only: the check cats this file in, together with AppLanguage.swift (the two plan
//  sentences resolve through it). Reused by P7 (My hours).
//

import Foundation

enum ViennaTime {
    /// "Europe/Vienna" is in every iOS the app can run on. The fallback exists only so a
    /// missing tz database cannot become a launch crash; the check pins that it is not used.
    static let zone: TimeZone = TimeZone(identifier: "Europe/Vienna") ?? TimeZone(secondsFromGMT: 3600) ?? .gmt

    /// Gregorian in Vienna's zone: the calendar every "same day?" question is asked of.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }()

    /// "14.07.2026" (de_AT) / "14 Jul 2026" (en_GB) / "Jul 14, 2026" (en_US) - the date as it is
    /// in Vienna.
    static func date(_ instant: Date, locale: Locale) -> String {
        formatter(.medium, .none, locale: locale).string(from: instant)
    }

    /// "08:00" (de_AT, en_GB) / "8:00 AM" (en_US) - the time as it is in Vienna.
    static func time(_ instant: Date, locale: Locale) -> String {
        formatter(.none, .short, locale: locale).string(from: instant)
    }

    /// Do these two instants fall on the same calendar day IN VIENNA? An end at exactly 00:00
    /// is already the next day, so a 22:00-00:00 assignment is a cross-day one.
    static func sameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// One DateFormatter per (style, locale): a list of up to 200 rows asks for hundreds, and
    /// building one is the expensive part. Main-thread only, like every caller.
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ dateStyle: DateFormatter.Style, _ timeStyle: DateFormatter.Style,
                                  locale: Locale) -> DateFormatter {
        let key = "\(dateStyle.rawValue)/\(timeStyle.rawValue)/\(locale.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = zone          // explicit: never the phone's (see the header)
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatters[key] = formatter
        return formatter
    }
}

/// The one line that says WHEN an assignment is. No relative words, no weekday, no duration.
enum ScheduleTimeLine {
    /// Within one Vienna day, compact: "<date> · <from>–<to>" (a middle dot, an UNSPACED en dash).
    /// Across midnight, long: "<date>, <from> – <date>, <to>" (a SPACED en dash).
    ///
    /// TWO NON-POSITIONAL KEYS that differ only by that dash's spacing, in Localizable.xcstrings
    /// as "%@ · %@–%@" and "%@, %@ – %@, %@" (the German values are Android's, verbatim, with
    /// positional markers). A dash typed with the wrong spacing here makes the lookup miss and
    /// ships English on a German phone with nothing to say so; checks/schedule-check.swift reads
    /// the two literals below out of this file as text and fails unless the catalogue holds
    /// exactly those keys. Copy the characters, do not retype them.
    static func text(from start: Date, to end: Date, locale: Locale) -> String {
        let date = ViennaTime.date(start, locale: locale)
        let from = ViennaTime.time(start, locale: locale)
        let to = ViennaTime.time(end, locale: locale)
        if ViennaTime.sameDay(start, end) {
            return AppLanguage.string("\(date) · \(from)–\(to)", locale: locale)
        }
        let endDate = ViennaTime.date(end, locale: locale)
        return AppLanguage.string("\(date), \(from) – \(endDate), \(to)", locale: locale)
    }
}
