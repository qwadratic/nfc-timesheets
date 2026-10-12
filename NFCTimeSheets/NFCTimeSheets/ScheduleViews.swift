//
//  ScheduleViews.swift
//  NFCTimeSheets
//
//  THE WORKER'S PLANNED ASSIGNMENTS (decision-80), as three self-contained views. Ported from
//  android/.../ui/WorkerHomeCards.kt `WorkerScheduleSummary` / `ScheduleCard` at 60f6886 (that
//  file, not the docs: the docs still describe a three-row summary).
//
//    ScheduleSummary        the collapsed "Next planned assignment · View" row, which expands in
//                           place into
//    ScheduleCard           "My schedule": the first assignment, an "All upcoming assignments"
//                           toggle when there are more, loading / empty / offline / error states
//                           and a refresh control. Rows are
//    ScheduleAssignmentRow  building, when, and the note when there is one.
//
//  NO SURFACE OF THEIR OWN, ON PURPOSE. No background, no corner radius, no fixed colour, no list
//  row styling: only text styles, semantic colours (.primary / .secondary / the tint) and
//  spacing. The CALLER supplies the container - a List section on the idle screen, the running
//  screen's card - so the Blue Hour reskin (B1-B5) can restyle where this lives without opening
//  this file. checks/schedule-check.swift fails on a hard-coded surface here.
//
//  DISPLAY ONLY. These views take a `ScheduleState` and a `retry` closure and nothing else. They
//  cannot start, stop or post a shift, they hold no reference to the store, and an assignment is
//  not a link into anything (Android: "the assignment is not a link; no tab, no reminder").
//
//  EVERY BUTTON IS .borderless: inside a List row a plain Button swallows the whole row, and
//  these rows hold several (the toggle, the refresh icon, Try again).
//
//  STRINGS: English sentence = key, German in Localizable.xcstrings (Android's, verbatim). A
//  control that changes label is an if/else of two literals, never a ternary of two: a ternary
//  of string literals picks the VERBATIM Text initialiser and ships English (TASK-298).
//

import SwiftUI

/// The collapsed row. `expanded` is its own @State, so ShiftScreen's once-a-minute TimelineView
/// redraw cannot collapse it.
struct ScheduleSummary: View {
    let state: ScheduleState
    let retry: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                // The action is spelled in words (View / Close), never a bare chevron: a label that
                // says what the control does is the one a VoiceOver user and a glove both get.
                //
                // ONE LINE when it fits; stacked when it does not. At the largest accessibility text sizes
                // the action word (never shrunk, it is the control's name) leaves the title a column a few
                // letters wide and "Einsatz" wraps one character per line - so the row falls back to the
                // title with the action under it instead.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Next planned assignment")
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if expanded {
                            Text("Close").fixedSize()
                        } else {
                            Text("View").fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next planned assignment")
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if expanded {
                            Text("Close")
                        } else {
                            Text("View")
                        }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if expanded {
                ScheduleCard(state: state, retry: retry)
            } else if case .loaded(let assignments) = state, let next = assignments.first {
                // Collapsed while loading, failed or empty: NOTHING under the row. The failure is
                // told where the worker asked for the schedule - the expanded card - not on the
                // home screen, where an old server without the route would nag on every launch.
                ScheduleAssignmentRow(assignment: next, showsNote: false)
            }
        }
    }
}

/// "My schedule". The first assignment only; with more than one, a toggle lists them all.
struct ScheduleCard: View {
    let state: ScheduleState
    let retry: () -> Void

    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("My schedule")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh assignments")
            }
            Text("Planned · Clock in separately")
                .font(.footnote)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A new state (a refresh, a retry, a fresh load on the next appearance) starts folded
        // again, as Android's `remember(state)` does.
        .onChange(of: state) { _, _ in showAll = false }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            Text("Loading assignments …")
        case .failed(let offline):
            if offline {
                Text("Could not load assignments without a connection.")
            } else {
                Text("Could not load assignments.")
            }
            // In place: the same card, the same control, a fresh request.
            Button("Try again", action: retry)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        case .loaded(let assignments):
            if assignments.isEmpty {
                Text("No assignments planned for the next 31 days.")
            } else {
                let shown = showAll ? assignments : Array(assignments.prefix(1))
                ForEach(shown) { assignment in
                    ScheduleAssignmentRow(assignment: assignment, showsNote: true)
                    if showAll { Divider() }
                }
                if assignments.count > 1 {
                    Button {
                        showAll.toggle()
                    } label: {
                        if showAll {
                            Text("Show less")
                        } else {
                            Text("All upcoming assignments")
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

/// One assignment: the building, when (Vienna time, ScheduleTimeLine), and the note in full
/// when it is not blank. Plain text throughout, one VoiceOver element.
struct ScheduleAssignmentRow: View {
    let assignment: WireScheduleAssignment
    let showsNote: Bool
    /// The app language's locale (decision-74): the plan line's date, times and joining words are in it.
    @Environment(\.locale) private var locale

    private var note: String { assignment.note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: assignment.locationName)
                .font(.headline)
            Text(verbatim: ScheduleTimeLine.text(from: assignment.startsAt, to: assignment.endsAt, locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if showsNote, !note.isEmpty {
                // The whole note, wrapped - an instruction cut off at one line is no instruction.
                Text(verbatim: assignment.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
