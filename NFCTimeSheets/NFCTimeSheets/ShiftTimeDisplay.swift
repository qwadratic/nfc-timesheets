//
//  ShiftTimeDisplay.swift
//  NFCTimeSheets
//
//  THE RUNNING SCREEN'S TIME, AS TYPOGRAPHY (TASK-365.11 / iOS B3). Ported from android/.../ui/
//  ShiftTimeDisplay.kt `ElegantTime` at 60f6886: zero-padded HH:MM large in tabular digits, the seconds
//  at about a third of that size on the same baseline, no card around it. The arithmetic - which two
//  strings, clamped at the 8 h deadline - is ShiftSignal.clockParts (Foundation-only, check-covered);
//  this file only draws them.
//
//  A PER-SECOND TimelineView AROUND ONLY THE DIGITS. This replaces `Text(timerInterval:)`, which the
//  system ticks for free but can only draw at one size. The screen above still redraws once a minute
//  (ShiftScreen's TimelineView, which has to flip the heading, the field and the words together at the
//  8 h boundary); this view is a CHILD with its own schedule, so the minute tick neither restarts nor
//  cuts it, and nothing outside this small view is invalidated by a second passing. The schedule is
//  anchored on the shift's own start, so a tick lands on a second boundary of the elapsed time.
//
//  ONE LINE, FITTED. A single Text (an AttributedString with two fonts) so the two runs share a
//  baseline and one `minimumScaleFactor` scales the whole line; its base size is a @ScaledMetric, so it
//  follows Dynamic Type up to the largest accessibility size and then shrinks to the width instead of
//  clipping - Android measures the text for the same reason.
//
//  HIDDEN FROM VOICEOVER, ON PURPOSE. A per-second change under VoiceOver is unusable; the card around
//  this view is ONE accessibility element with a label recomputed once a minute (ShiftScreen.clock),
//  and it is that label - not these digits - that is read.
//
//  NO SURFACE, NO WORDS: the ink is the caller's (the field's), and there is no user-visible string.
//

import SwiftUI

struct ShiftTimeDigits: View {
    let startTime: Date
    /// Past 8 h (or the server flagged it): "08:00" and a small "00+", not a running number - a ticking
    /// digit on a row that is already out of payroll would be a lie about it.
    let overdue: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 72

    var body: some View {
        Group {
            if overdue {
                Self.line(ShiftSignal.overdueClock, size: size)
            } else {
                TimelineView(.periodic(from: startTime, by: 1)) { context in
                    Self.line(ShiftSignal.clockParts(from: startTime, to: context.date), size: size)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .accessibilityHidden(true)
    }

    /// "HH:MM" regular and large, then "SS" medium at 32% - Android's `fontSize * .32f` - in one Text.
    /// The ink is NOT set here: it is the foreground style of whatever this sits in.
    private static func line(_ parts: (main: String, seconds: String), size: CGFloat) -> Text {
        var large = AttributedString(parts.main)
        large.font = .system(size: size, weight: .regular).monospacedDigit()
        large.kern = -0.8
        var gap = AttributedString(" ")
        gap.font = .system(size: size * 0.32, weight: .medium)
        var small = AttributedString(parts.seconds)
        small.font = .system(size: size * 0.32, weight: .medium).monospacedDigit()
        return Text(large + gap + small)
    }
}
