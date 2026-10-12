//
//  ConfirmationMark.swift
//  NFCTimeSheets
//
//  THE RING-THEN-CHECK, drawn (decision-83, TASK-365.8 / iOS P7). Ported from Android's
//  ShiftTimeDisplay.kt `PaymentConfirmation` and `ShiftTimeDisplay` at 60f6886. WHEN it may play and
//  every number below is ConfirmationMotion.swift (Foundation-only, check-covered); this file only
//  draws a frame and hosts the clock.
//
//    ConfirmationMark       one frame: a faint full ring, the arc that draws over it, the check
//                           that draws inside it. 88 pt, 2.8 pt stroke, like Android's 88 dp.
//    .confirmationMotion()  wraps the time (clock-in) or the receipt's text (clock-out): while the
//                           motion runs the content is held back and fades up as the pair leaves,
//                           and the mark is drawn over it.
//
//  THE INK IS THE CALLER'S AND IT IS NEVER GREEN (decision-60: green is retired as "running").
//  Both call sites pass `.primary`. The mark is `accessibilityHidden`: the time, its spoken label
//  and the receipt's words exist the whole time - a screen reader is never told a ring is
//  "loading", and never waits for it.
//
//  PRESENTATION ONLY. Nothing here reads or writes a shift, and the hosting modifier takes values:
//  the identity, whether the row is CONFIRMED, and when the event happened. It cannot hold a tap, a
//  sync, a signal or a navigation back - it only draws and, before it draws anything, writes the
//  identity it was given into the preference (`ConfirmationMotion.claim`).
//
//  TWO RULES THE HOST FOLLOWS, and the check reads them as text:
//    - THE IDENTITY IS CLAIMED BEFORE THE MOTION STARTS, and under Reduce Motion too. `claim` writes
//      it; only then is `startedAt` set, and only when `animates(_:reduceMotion:)` says so. A screen
//      that animated first and recorded later would replay after a crash, a tab return, a resume.
//    - THE ANIMATION CLOCK LIVES HERE, in a child of the screen, not in the screen. The running
//      screen redraws once a minute inside a TimelineView and LogView is rebuilt on every @Query
//      publish; @State kept in this modifier survives both, so a minute tick can neither restart
//      the motion nor cut it short.
//
//  NO SURFACE OF ITS OWN. No background, card, corner radius or fixed colour; the caller supplies
//  the container, so the Blue Hour reskin (B1-B5) restyles where this lives without opening it.
//

import SwiftUI

// MARK: - One frame

struct ConfirmationMark: View {
    let stage: ConfirmationMotion.Stage
    let ink: Color

    private static let size: CGFloat = 88
    private static let lineWidth: CGFloat = 2.8

    var body: some View {
        // Android insets the ring by two stroke widths each side; the check is drawn in the whole box.
        let ring = Self.size - 4 * Self.lineWidth
        ZStack {
            Group {
                Circle()
                    .stroke(ink.opacity(0.12), lineWidth: Self.lineWidth)
                // A circle's trim starts at 3 o'clock and runs clockwise, exactly like Android's
                // drawArc angles: rotate the start to 12 o'clock plus 25 deg of the ring's progress.
                Circle()
                    .trim(from: 0, to: stage.ringSweepDegrees / 360)
                    .stroke(ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(stage.ringStartDegrees))
            }
            .frame(width: ring, height: ring)
            ConfirmationCheck()
                .trim(from: 0, to: stage.check)
                .stroke(ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Self.size, height: Self.size)
        .scaleEffect(stage.markScale)
        .offset(y: stage.markLift)
        .opacity(stage.markOpacity)
        .accessibilityHidden(true)
    }
}

/// Android's three points, as fractions of the 88 dp box: (.29,.50) -> (.44,.64) -> (.72,.35).
struct ConfirmationCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.35))
        return path
    }
}

// MARK: - The host

extension View {
    /// Plays the ring-then-check over this view when - and only when - `confirmed` is a CLEAN ACK
    /// and `identity` is new (ConfirmationMotion.decide). `eventTime` is the moment the shift
    /// started (clock-in) or finished (clock-out).
    func confirmationMotion(kind: ConfirmationMotion.Kind, identity: String, confirmed: Bool,
                            eventTime: Date, ink: Color) -> some View {
        modifier(ConfirmationMotionHost(kind: kind, identity: identity, confirmed: confirmed,
                                        eventTime: eventTime, ink: ink))
    }
}

private struct ConfirmationMotionHost: ViewModifier {
    let kind: ConfirmationMotion.Kind
    let identity: String
    let confirmed: Bool
    let eventTime: Date
    let ink: Color

    /// Android's animator duration scale of 0: the stable state, no animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil = settled. The only animation state, and it lives HERE (see the header).
    @State private var startedAt: Date?

    /// Android keys its effect on (identity, confirmed): either changing starts a fresh decision.
    private struct Trigger: Equatable {
        let identity: String
        let confirmed: Bool
    }

    func body(content: Content) -> some View {
        // Paused when settled: one render, no frames.
        TimelineView(.animation(paused: startedAt == nil)) { timeline in
            let progress = startedAt.map { ConfirmationMotion.progress(since: $0, now: timeline.date) } ?? 1
            let stage = ConfirmationMotion.stage(progress: progress)
            content
                .opacity(stage.contentOpacity)
                .offset(y: stage.contentLift)
                .overlay {
                    if !stage.isSettled { ConfirmationMark(stage: stage, ink: ink) }
                }
        }
        .onChange(of: Trigger(identity: identity, confirmed: confirmed), initial: true) { _, _ in
            begin()
        }
        // Drops the clock when the motion is over (or immediately when the view returns after it
        // already was), so a settled view is a paused TimelineView and nothing more.
        .task(id: startedAt) {
            guard let started = startedAt else { return }
            let remaining = ConfirmationMotion.duration - Date.now.timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            if !Task.isCancelled { startedAt = nil }
        }
    }

    private func begin() {
        startedAt = nil                       // a new identity or a flip back to pending: stable at once
        guard confirmed else { return }       // pending / failed / blocked: never a check
        // CLAIM FIRST. The identity is in the preference before anything below can animate.
        let decision = ConfirmationMotion.claim(kind, identity: identity, confirmed: confirmed, eventTime: eventTime)
        guard ConfirmationMotion.animates(decision, reduceMotion: reduceMotion) else { return }
        startedAt = .now
    }
}
