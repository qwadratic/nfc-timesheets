//
//  MyHoursView.swift
//  NFCTimeSheets
//
//  "MY HOURS", drawn (decision-83, TASK-365.8 / iOS P7). Ported from Android's TimeSheetApp.kt
//  `MyHoursScreen` / `MyHoursRow` at 60f6886: a window sentence, then loading / failed / loaded, and
//  per row the building, the status word, the date, the start, the end (or "No end yet") and the
//  duration (finished rows only) - in Europe/Vienna through ViennaTime, whatever zone the phone is in.
//  The state, the fetch and the failure mapping are MyHours.swift; this file only draws them.
//
//  PUSHED FROM SETTINGS, so the system supplies the navigation bar and its back button (Android
//  draws an explicit Back because it has no stack). `.task` asks the server on EVERY entry and
//  the store lives in this view's own @State: popping the screen drops the list, so nothing is
//  cached - and a change of worker recreates all four tabs (the TabView's .id(worker.id)) before
//  this can show a colleague's hours.
//
//  READ-ONLY. No total, no rate, no euro amount, no control that writes a shift. A row is not a
//  link into anything.
//
//  NO SURFACE OF ITS OWN, ON PURPOSE (the rule ScheduleViews, PendingNoticeView and
//  DeliveryStatusViews follow): no background, card or corner radius, no fixed colour. The status
//  and "Manual" go through the shared `pill`, so the Blue Hour reskin (B1-B5) restyles them in one
//  place and this file never has to be opened. The container is the system List.
//
//  STRINGS: English sentence = key, German in Localizable.xcstrings (Android's, verbatim). A word
//  that changes is a `switch` of literals, never a ternary of two: a ternary of string literals
//  picks the VERBATIM Text initialiser and ships English (TASK-298). The building is DATA and goes
//  through Text(verbatim:), never the catalogue.
//

import SwiftUI

struct MyHoursView: View {
    /// The signed-in worker this screen was pushed for. The request is made as THEM and an answer
    /// is dropped if somebody else holds the session by the time it lands (LoadGuard).
    let worker: WireWorker

    @Environment(Session.self) private var session
    @State private var store = MyHoursStore()

    var body: some View {
        List {
            // States the 60-day window and that it is the SERVER's list, which distinguishes this
            // from History: the phone's own log of what it wrote.
            Section {
                Text("Your shifts from the last 60 days, as stored on the server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch store.state {
            case .loading:
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            case .failed(let offline):
                Section {
                    MyHoursFailure(offline: offline, retry: load)
                }
            case .loaded(let rows):
                if rows.isEmpty {
                    Section {
                        Text("No shifts in this period.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(rows) { MyHoursRowView(row: $0) }
                    }
                }
            }
        }
        .navigationTitle("My hours")
        .task { load() }
        .onDisappear { store.cancel() }
    }

    /// THE ONE TRIGGER: entry, and the Refresh button. Returns at once; the answer lands in the store.
    private func load() {
        let session = session
        store.load(for: worker.id) { session.worker?.id }
    }
}

/// The failure sentence and the one retry control. The sentence is announced when it appears
/// (Android: an assertive live region); a Refresh press asks the server again.
private struct MyHoursFailure: View {
    let offline: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if offline {
                Text("No connection. Your hours can't be loaded right now.")
            } else {
                Text("Your hours could not be loaded.")
            }
            Button("Refresh", action: retry)
                .buttonStyle(.bordered)
        }
        .onAppear { announce() }
    }

    private func announce() {
        var spoken: AttributedString
        if offline {
            spoken = AttributedString(AppLanguage.string("No connection. Your hours can't be loaded right now."))
        } else {
            spoken = AttributedString(AppLanguage.string("Your hours could not be loaded."))
        }
        spoken.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(spoken).post()
    }
}

/// One row: building, status word (and "Manual"), date, start, end, duration - never a rate, never a total.
struct MyHoursRowView: View {
    let row: MyHours.Row
    /// The app language's locale (decision-74): Vienna's date and times, formatted in it.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                // Data, not copy: the building as the server names it, else "Unknown location".
                if let building = row.building {
                    Text(verbatim: building).font(.headline)
                } else {
                    Text("Unknown location").font(.headline)
                }
                Spacer()
                // decision-56 section 5, as on every other list of shifts.
                if row.manual { pill("Manual", .blue) }
                // The WORD always carries the meaning on its own; the colour is the second signal.
                statusPill
            }
            Text("Date: \(ViennaTime.date(row.start, locale: locale))").font(.caption)
            Text("Start: \(ViennaTime.time(row.start, locale: locale))").font(.caption)
            if let end = row.end {
                Text("End: \(ViennaTime.time(end, locale: locale))").font(.caption)
            } else {
                Text("No end yet").font(.caption)
            }
            // Omitted - not zero, not fake - for the running row.
            if let duration = row.duration {
                Text("Duration: \(fmtDur(duration))").font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusPill: some View {
        switch row.status {
        case .running: pill("In progress", .orange)
        case .autoClosed: pill("Auto-closed", .red)
        case .corrected: pill("Corrected", .purple)
        case .closed: pill("Closed", .secondary)
        }
    }
}
