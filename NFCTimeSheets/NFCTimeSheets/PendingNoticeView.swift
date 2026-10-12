//
//  PendingNoticeView.swift
//  NFCTimeSheets
//
//  The line under the running clock - "Saved on this phone · not yet confirmed", or the row's
//  own delivery problem in the worker's words - and the one Refresh button that retries it.
//  The DECISION whether it exists and what it says is PendingNotice.swift; this file only draws
//  the answer.
//
//  NO SURFACE OF ITS OWN, deliberately: no background, no card, no hard-coded colour except the
//  red of a refused row. ShiftScreen places it directly after the clock card, and the Blue Hour
//  reskin (B3) restyles the container it sits in, not this view - the same rule ScheduleViews
//  follows. checks/pending-notice-check.swift fails on a surface creeping in.
//
//  IT IS A SEPARATE VIEW, NOT A PART OF THE CLOCK CARD, because that card is one accessibility
//  element with its children ignored: anything inside it would be unreachable to VoiceOver and
//  the button could not be focused. Here the line is one element, the button another.
//
//  DISPLAY ONLY. The button calls the closure it is given - the same refresh as pull-to-refresh -
//  and nothing here reads, hides, disables or gates a control elsewhere on the screen.
//

import SwiftUI

struct PendingNoticeView: View {
    let content: PendingNotice.Content
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Colour is never the only signal: the sentence beside this says it. Shown only
                // for a refused row, because that is the one state where nobody is retrying.
                if case .problem(_, blocked: true) = content {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                Text(verbatim: text)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            Button("Refresh", action: onRefresh)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        // Android marks this line a POLITE live region: it is read out when it appears or
        // changes, without cutting off what VoiceOver is already saying. SwiftUI has no
        // live-region trait, so the equivalent is a low-priority announcement.
        .onAppear { announce() }
        .onChange(of: text) { announce() }
    }

    /// The sentence. A row's own error is ALREADY localised (Sync.swift stores
    /// APIFailure.workerMessage), so it is drawn verbatim and never looked up again.
    private var text: String {
        switch content {
        case .savedLocally: return String(localized: "Saved on this phone · not yet confirmed")
        case .problem(let sentence, _): return sentence
        }
    }

    private func announce() {
        var spoken = AttributedString(text)
        spoken.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(spoken).post()
    }
}
