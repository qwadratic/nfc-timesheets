//
//  DeliveryStatusViews.swift
//  NFCTimeSheets
//
//  WHAT THE PHONE STILL HOLDS, drawn (decision-82, TASK-365.7 / iOS P6). Ported from Android's
//  ui/DeliveryStatus.kt at 60f6886: up to two compact, tappable count rows - blocked first - and a
//  details sheet with ONE state-specific explanation, the earliest shift start and the last attempt.
//  The counting and the wording DECISION are PendingWork.swift (Foundation-only, check-covered);
//  this file only draws the answer.
//
//    DeliveryStatusRows     renders NOTHING when the phone holds nothing, otherwise a blocked row
//                           and/or a waiting row; each opens
//    DeliveryDetailsSheet   "Delivery": the blocked count + what to do, the waiting count + exactly
//                           one sentence, a divider, the earliest start, the last attempt, Close.
//
//  NO SURFACE OF THEIR OWN, ON PURPOSE (the rule ScheduleViews and PendingNoticeView follow): no
//  background, no card, no corner radius, no fixed colour but the red of a BLOCKED row. The
//  CALLER supplies the container - a List row on the idle screen, the Form on the sign-in screen,
//  the running screen's stack - so the Blue Hour reskin (B1-B5) restyles where this lives without
//  opening this file. checks/pending-work-check.swift fails on a surface creeping in.
//
//  COLOUR IS NEVER THE ONLY SIGNAL: a blocked row says "need your office" in words and carries a
//  glyph; the red only reinforces it.
//
//  DISPLAY ONLY. These views take rows and a flag and nothing else: they hold no store, no context
//  and no API, they cannot start, stop, post, retry or delete anything, and a row is not a link
//  into a shift. Closing the sheet deletes nothing. The one thing they read besides their input is
//  the last-attempt stamp (DeliveryAttempt), through @AppStorage so a refresh that fails again
//  updates "Last attempt" while the sheet is open.
//
//  THE WORDS ARE TRUE ON iOS: there is no background delivery here, so no sentence in this file
//  promises one (Android's "your phone will try again automatically" and its force-stop note were
//  not ported). "Open the app" is the only retry the sheet talks about, because it is the only one.
//
//  STRINGS: English sentence = key, German in Localizable.xcstrings (Android's, with the one
//  deliberate exception named in decision-82). A control or sentence that changes is an if/else or
//  a switch of literals, never a ternary of two: a ternary of string literals picks the VERBATIM
//  Text initialiser and ships English (TASK-298).
//

import SwiftUI

/// The rows. `rows` is the DEVICE-WIDE outbox (WorkerScope.deviceWide, mapped by Shift.deliveryRow);
/// `signedOut` is true only on the sign-in screen, where there is no session to retry under.
struct DeliveryStatusRows: View {
    let rows: [PendingRow]
    let signedOut: Bool

    /// The last-attempt stamp (0 = never). A property wrapper so the sheet below updates the moment
    /// a push stamps it, even when no row changed.
    @AppStorage(DeliveryAttempt.defaultsKey) private var lastAttemptSeconds: Double = 0

    var body: some View {
        let summary = PendingWork.summarise(rows, lastAttemptAt: DeliveryAttempt.date(seconds: lastAttemptSeconds))
        // Nothing at all when the phone holds nothing - no empty section, no gap, no sheet. The
        // content below owns the sheet's @State, so when the last row is delivered the sheet goes
        // with it and a LATER unsent row can never reopen a stale one.
        if !summary.isEmpty {
            DeliveryStatusContent(summary: summary, signedOut: signedOut)
        }
    }
}

private struct DeliveryStatusContent: View {
    let summary: PendingWork.Summary
    let signedOut: Bool

    @State private var showDetails = false

    var body: some View {
        // EVERY BUTTON IS EXPLICITLY STYLED: inside a List or Form row a default-style Button swallows
        // the whole row, and this row holds two. The border shape is the system's rounded rectangle, not
        // the capsule: at the accessibility text sizes a count wraps to several lines and a capsule
        // turns into an ellipse around them.
        VStack(spacing: 8) {
            if summary.blocked > 0 {
                Button { showDetails = true } label: { blockedLabel }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.large)
                    .tint(.red)
            }
            if summary.waiting > 0 {
                Button { showDetails = true } label: { waitingLabel }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showDetails) {
            DeliveryDetailsSheet(summary: summary, signedOut: signedOut)
        }
    }

    // The two labels are separate on purpose: a plural count is a LocalizedStringKey with an Int
    // interpolation, so each one is its own literal and the catalogue picks one/other (CLDR).

    private var blockedLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.octagon.fill").accessibilityHidden(true)
            Text("\(summary.blocked) shifts need your office")
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private var waitingLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text("\(summary.waiting) shifts still on this phone")
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }
}

/// "Delivery". The content scrolls (200% Dynamic Type is far taller than a .medium detent), and the
/// Close button is OUTSIDE the scroll view, so it is always on screen: a sheet whose only visible way
/// out is below the fold is a trap for a worker who does not know the drag gesture.
struct DeliveryDetailsSheet: View {
    let summary: PendingWork.Summary
    let signedOut: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delivery")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    if summary.blocked > 0 {
                        // Error styling AND words: the count says "need your office", and the paragraph
                        // under it says what the worker has to do - tell the office the time below.
                        Text("\(summary.blocked) shifts need your office")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("Your office needs to review these entries. They remain on this phone and are not sent again. Please tell your office the time shown below.")
                            .font(.body)
                    }

                    if summary.waiting > 0 {
                        Text("\(summary.waiting) shifts still on this phone")
                            .font(.headline)
                        // EXACTLY ONE sentence (PendingWork.waitingSentence), and none of them promises
                        // automatic delivery: iOS has no background delivery.
                        switch PendingWork.waitingSentence(for: summary, signedOut: signedOut) {
                        case .signIn:
                            Text("Sign in with the same account so these entries can be delivered.")
                                .font(.body)
                        case .notActive:
                            Text("Automatic delivery is not currently active. Open the app with an internet connection to try delivery again.")
                                .font(.body)
                        case nil:
                            EmptyView()
                        }
                    }

                    Divider()

                    if let oldest = summary.oldestStart {
                        Text("Earliest shift start: \(oldest.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                    }
                    if let attempt = summary.lastAttemptAt {
                        Text("Last attempt: \(attempt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                    } else {
                        Text("No delivery attempt yet.")
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Button { dismiss() } label: {
                Text("Close").frame(maxWidth: .infinity)
            }
            .buttonStyle(.workerPrimary)
            .padding(24)
        }
        .presentationDetents([.medium, .large])
    }
}
