//
//  ShiftScreen.swift
//  NFCTimeSheets
//
//  What the app looks like while a shift is running. Not a pill on a row - THE screen.
//
//  The failure this exists to prevent: a worker taps in at 06:02, pockets the phone, goes
//  home, and nothing on that phone ever mentions the shift again. At 14:02 the server
//  closes it, it leaves payroll (decision-10), and the office pays for a manual
//  correction. So while a shift runs the app is unmistakable from across a room and has
//  exactly one subject.
//
//  THE LOCK IS WORK DISCIPLINE, NOT SECURITY. Nothing here is enforcement and nothing
//  here traps anybody: the resolver, the materials tab, sign-out and the help text are
//  reachable at every moment, as labelled controls rather than gestures. The one thing
//  that goes away is History, because nothing in it is time-critical. See
//  ShiftSignal.visibleTabs, which is where that rule is written down and check-covered.
//

import SwiftUI
import UIKit    // openSettingsURLString - the one link out of the "notifications are off" card

struct ShiftScreen: View {
    let running: RunningShift
    /// Shifts the 8h timer closed that nobody has confirmed yet (decision-10). Shown in
    /// EVERY state, including this one - a locked screen may never hide the resolver.
    let unresolvedCount: Int
    let onResolve: () -> Void
    /// The "your open shift was moved to another building" sentence, when there is one.
    let notice: String?
    let onDismissNotice: () -> Void
    /// decision-56: end this shift NOW, without a tag. The confirmation lives here; the
    /// caller only ever hears about a decision the worker already confirmed.
    let onManualStop: () -> Void
    /// The FOREGROUND scan (TapScanner.swift): close this shift by holding the card to the
    /// phone while the app is open, instead of backgrounding it so iOS can open the link.
    /// It resolves a tag and posts it to TapInbox - the same mailbox the background tap
    /// uses - so this button opens no shift logic of its own.
    let onScan: () -> Void
    /// What the PHONE still holds, device-wide (decision-82): every account's unsent and refused rows,
    /// as values. Drawn as the two delivery count rows after the resolver card and nowhere else - the
    /// clock, the controls and the signals know nothing about it, and an empty outbox draws nothing.
    let deliveryRows: [PendingRow]
    /// The OPEN row's delivery problem, already a worker-facing sentence (Sync.swift
    /// `APIFailure.workerMessage`) - never a code - and whether nobody is retrying it
    /// (`syncBlocked`: a human has to act, so it is drawn red). Together with
    /// `running.pendingConfirmation` they decide the words under the clock (PendingNotice) and
    /// NOTHING ELSE: no control is hidden or disabled by them, and the clock keeps counting.
    let syncError: String?
    let syncBlocked: Bool
    /// The same refresh pull-to-refresh runs (roster, adopt, push the queue, re-arm). The one
    /// retry control on this screen.
    let onRefresh: () -> Void
    /// decision-80: the worker's PLANNED assignments, for display and nothing else - this screen
    /// never branches on them, and the tap, the sync and the signals know nothing about them. The
    /// state and the reload closure come from LogView's ScheduleStore, so the idle list and this
    /// screen show one answer.
    let schedule: ScheduleState
    let onReloadSchedule: () -> Void

    @Environment(ShiftSignalCenter.self) private var signals
    @Environment(\.openURL) private var openURL
    /// The app language's locale (decision-74): the notice card's sentence was made in the language
    /// in force when the shift switched buildings, so it is said again in this one.
    @Environment(\.locale) private var locale
    /// The phone's appearance. The field's pieces are drawn in a DARK one (`onField`) while the neutral
    /// cards and everything that presents a sheet are NOT - on a light phone the cards are light cards
    /// with dark text on a dark field, exactly like Android's neutral WorkerCards on ShiftBrand.Container.
    @Environment(\.colorScheme) private var systemScheme
    /// The animated gradient (the flag-gated option) holds still under Reduce Motion: the field is
    /// already a complete screen without it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingStop = false
    /// Shift help is an inline disclosure, not a dialog: SwiftUI drops an alert (and a second sheet) that
    /// presents while the decision-10 resolver sheet does, and help must never be the thing that eats it.
    @State private var showHelp = false
    /// The grace before "Not confirmed yet" may be CLAIMED (ShiftSignal.isPending): iOS writes the
    /// row before the POST, so an online tap is unacknowledged for one request and must not flash
    /// a warning. Set by the .task(id:) below after PendingNotice.grace; a sync error or an old
    /// start skips the wait (PendingNotice.graceElapsedAtOnce, read in `body`).
    @State private var graceElapsed = false

    /// decision-60: the flag no longer decides the COLOUR - blue is the colour, flag or no
    /// flag. What it still decides is whether that blue is animated (the gradient below).
    /// Read straight out of the cache rather than passed in, so the call site (and every
    /// preview) keeps the plain screen for free.
    @AppStorage(FeatureFlags.defaultsKey(FeatureFlags.funShiftScreen))
    private var funTheme = false

    /// THE WHOLE SCREEN is inside one TimelineView, ticking once a minute, and that is
    /// deliberate rather than tidy: the 8h boundary has to flip the heading, the colour,
    /// the words AND the clock together. An earlier shape put the TimelineView around only
    /// the clock, and a shift that crossed 8 hours while the worker was looking at the
    /// screen kept a green "Clocked in" header above a stopped timer until something else
    /// happened to redraw the body.
    ///
    /// Once a minute, not once a second: the digits tick in their OWN small timeline
    /// (ShiftTimeDisplay.swift), so nothing here needs to keep up with them.
    var body: some View {
        TimelineView(.periodic(from: running.startTime, by: 60)) { context in
            // overdue > pending > running (ShiftSignal.presentation). The tick's date decides
            // the 8h boundary; the REAL now decides whether an old start skips the grace, so a
            // screen reopened on a long-unacknowledged shift never says "Clocked in" first.
            let hasError = syncError?.isEmpty == false
            let graceOver = graceElapsed
                || PendingNotice.graceElapsedAtOnce(startedAt: running.startTime, now: .now, hasSyncError: hasError)
            let presentation = ShiftSignal.presentation(of: running, now: context.date,
                                                        graceElapsed: graceOver, hasSyncError: hasError)
            let overdue = presentation == .overdue
            // Colour is the SECOND signal, never the only one - the state is spelled out
            // in words directly under the clock, so this screen still reads in greyscale.
            //
            // THE FIELD IS FIXED (decision-60 section 2, Android ShiftBrand): a dark blue that is the same
            // in light and in dark mode, with light ink, as NAMED colour sets - never a literal, never
            // the system's palette, never conditional on fun_shift_screen. GREEN IS RETIRED (decision-60
            // section 1): nothing in this file is `.green`, and no raw `.blue` stands for "running".
            //
            // OVERDUE keeps its own consequence and is still a colour AND words: red ink - on the
            // neutral error field with the flag off (Android errorContainer / onErrorContainer), over
            // the animated blue with it on (FunShift.Overdue is the dark variant of the same ink).
            // `tint` is the INK on the field; its name is kept because the three pieces below take it.
            let neutral = overdue && !funTheme
            let tint: Color = overdue ? Self.overdueInk : Self.onField
            let field: Color = neutral ? Self.overdueField : Self.field

            // ScrollView, not a fixed stack: at 200% Dynamic Type this content is far
            // taller than the screen, and a locked screen that clips its own instructions
            // is worse than no lock at all.
            //
            // THE FIELD'S INK IS APPLIED PIECE BY PIECE (`onField`), never to the whole stack: the delivery
            // rows present a sheet and the cards are neutral, and a sheet inherits its presenter's
            // foreground style and colour scheme while its background stays the PHONE's - light ink on a
            // light sheet. So only the pieces that sit directly on the field are drawn in its ink and in a
            // dark scheme (the semantic colours inside PendingNoticeView carry no colour of their own).
            let scheme: ColorScheme = neutral ? systemScheme : .dark
            ScrollView {
                VStack(spacing: 24) {
                    header(presentation: presentation, tint: tint)
                        .onField(ink: tint, field: field, scheme: scheme)
                    clock(presentation: presentation, now: context.date)
                        .onField(ink: tint, field: field, scheme: scheme)
                    // A SEPARATE view, AFTER the clock block and not inside it: the block is one
                    // accessibility element (children: .ignore), which would swallow a Refresh
                    // button put in there - VoiceOver could not focus it and the line would be
                    // read as part of the time. Separate, it is its own element and the button
                    // is its own control.
                    if let content = PendingNotice.content(for: running, graceElapsed: graceOver,
                                                           syncError: syncError, syncBlocked: syncBlocked) {
                        PendingNoticeView(content: content, onRefresh: onRefresh)
                            .onField(ink: tint, field: field, scheme: scheme)
                    }
                    instruction(tint: tint)
                        .onField(ink: tint, field: field, scheme: scheme)
                    scanButton
                        .onField(ink: tint, field: field, scheme: scheme)
                    stopButton
                        .onField(ink: tint, field: field, scheme: scheme)
                    if let notice { noticeCard(notice) }
                    if unresolvedCount > 0 { resolverCard }
                    // decision-82. Not conditional HERE: the view draws nothing when the phone holds
                    // nothing, and the running stack keeps exactly the four conditionals it had.
                    // Directly on the field, and it presents a sheet - so the ink reaches it as its TINT only
                    // (the bordered rows read in it) and nothing else is inherited by what it presents.
                    DeliveryStatusRows(rows: deliveryRows, signedOut: false)
                        .tint(tint)
                    if signals.outOfAppSignalsSilenced { notificationsOffCard }
                    scheduleCard
                    helpButton
                        .onField(ink: tint, field: field, scheme: scheme)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(background(overdue: overdue, field: field).ignoresSafeArea())
            // Light status-bar icons over the dark field, even in light mode (Android WorkerStatusBar).
            .toolbarColorScheme(neutral ? nil : .dark, for: .navigationBar)
        }
        // The permission moment. AFTER the first clock-in, from the screen that is already
        // explaining what the reminder buys, and never on the tap path itself - the gate
        // is ShiftSignal.shouldAskForNotifications and it is check-covered. A worker asked
        // at a door at 06:02 with gloves on says no once, permanently.
        .task {
            await signals.requestAuthorizationIfNeeded()
        }
        // The grace itself (ShiftSignal.isPending). Restarts when the flag flips or a DIFFERENT
        // shift takes the screen (a switch keeps the flag true, so the id carries the start too),
        // and a cancelled sleep never claims anything.
        .task(id: GraceKey(startTime: running.startTime, pending: running.pendingConfirmation)) {
            graceElapsed = false
            guard running.pendingConfirmation else { return }
            try? await Task.sleep(for: .seconds(PendingNotice.grace))
            if !Task.isCancelled { graceElapsed = true }
        }
    }

    private struct GraceKey: Equatable {
        let startTime: Date
        let pending: Bool
    }

    // MARK: - Background

    /// The fixed field ink and the two overdue colours - named sets, one place to change each.
    private static let field = Color("ShiftField")
    private static let onField = Color("ShiftOnField")
    private static let overdueField = Color("ShiftOverdueField")
    private static let overdueInk = Color("ShiftOverdueInk")

    /// The one blue the animated gradient is drawn in (the same family as AccentColor, decision-60
    /// section 1). Only BlueDrift uses it now: the plain screen is `field`.
    private static let running = Color("ShiftRunning")

    /// Flag OFF: the solid field. Flag ON: the same field with the slow dark-to-light blue breathing
    /// over it (decision-60 section 3). It is a BACKGROUND and stays one: everything that says what
    /// state the shift is in - the heading words, the time, "Running", the resolver - is drawn over it,
    /// so nothing here can sit between the worker and the words.
    @ViewBuilder
    private func background(overdue: Bool, field: Color) -> some View {
        if funTheme && !reduceMotion {
            ZStack {
                field
                BlueDrift(tint: overdue ? .red : Self.running)
                    .accessibilityHidden(true)     // decoration; VoiceOver reads the words
            }
        } else {
            field
        }
    }

    // MARK: - The three states, in words
    //
    // overdue > pending > running (ShiftSignal.presentation), each said in THREE places: the
    // heading, the word under the clock and what VoiceOver reads for the clock. They are three
    // small functions of the presentation and nothing else, so a restyle of header() / clock()
    // keeps the words and only moves where they are drawn.

    private func headingText(_ presentation: ShiftPresentation) -> Text {
        switch presentation {
        case .overdue: return Text("Over 8 hours")
        case .pending: return Text("Not confirmed yet")
        case .running: return Text("Shift in progress")
        }
    }

    /// The sentence under the clock. "Time recorded on this phone" - not "Running" - while the
    /// start is only on the phone: the clock beside it still counts, from the LOCAL start.
    private func stateWord(_ presentation: ShiftPresentation) -> Text {
        switch presentation {
        case .overdue: return Text("This shift passed 8 hours and was closed automatically. It will not be paid until you confirm when you actually finished.")
        case .pending: return Text("Time recorded on this phone")
        case .running: return Text("Running")
        }
    }

    private func spokenState(_ presentation: ShiftPresentation, elapsed: (hours: Int, minutes: Int)) -> Text {
        switch presentation {
        case .overdue:
            return Text("Shift at \(running.locationName) passed 8 hours and was closed automatically. Confirm when you finished.")
        case .pending:
            return Text("\(elapsed.hours) hours and \(elapsed.minutes) minutes recorded on this phone for \(running.locationName). Not confirmed by the office yet.")
        case .running:
            return Text("Shift running for \(elapsed.hours) hours \(elapsed.minutes) minutes at \(running.locationName)")
        }
    }

    // MARK: - Pieces

    /// A QUIET state heading, the site name one step smaller than it used to be, the start time
    /// (Android: labelLarge at 80% ink, the building at 24 sp medium, "Begonnen um HH:mm"). The state is
    /// still said here AND under the clock AND to VoiceOver - the heading just no longer shouts it.
    private func header(presentation: ShiftPresentation, tint: Color) -> some View {
        VStack(spacing: 6) {
            headingText(presentation)
                .font(WorkerStyle.Typeface.label)
                .foregroundStyle(tint.opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            Text(running.locationName)
                .font(.title2.weight(.medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
            Text("Started \(AppLanguage.formatted(running.startTime, time: .shortened, locale: locale))")
                .font(.callout)
                .foregroundStyle(tint.opacity(0.8))
        }
    }

    /// The dominant element on the screen, and the whole reason this screen exists - now typography
    /// on the field, with no card behind it: the label "TIME WORKED", HH:MM large, the seconds small
    /// (ShiftTimeDigits), then the state word.
    ///
    /// The digits tick once a second in their OWN small TimelineView. The whole block is ONE
    /// accessibility element and the digits are inside it rather than beside it, because a per-second
    /// change under VoiceOver is unusable; its label is recomputed once a minute from `now`, and
    /// updating a label is not an announcement, so nothing is interrupted.
    ///
    /// A PENDING start is drawn exactly like a running one - the same ticking digits, counting from
    /// the local start - and only the word under them and the spoken label change.
    private func clock(presentation: ShiftPresentation, now: Date) -> some View {
        let elapsed = ShiftSignal.elapsed(from: running.startTime, to: now)
        return VStack(spacing: 10) {
            Text("TIME WORKED")
                .font(WorkerStyle.Typeface.caption)
                .opacity(0.8)
            // No running clock on a shift the 8h timer has closed (or is about to): a ticking number
            // there would be a lie about a row that is already out of payroll until a human fixes it.
            ShiftTimeDigits(startTime: running.startTime, overdue: presentation == .overdue)
            stateWord(presentation)
                .font(.callout)
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
        // decision-83 (P7): the one-shot ring-then-check over the digits, ONLY after a clean server
        // acknowledgement of THIS start (ShiftSignal.isConfirmed: the open landed, no error, not past
        // 8 hours) and only for an event under 45 s old, once per start. Presentation only: the
        // digits still tick, the block is still one accessibility element, nothing waits on it. The
        // animation clock lives in the modifier, a child, so this minute tick cannot restart it.
        .confirmationMotion(
            kind: .clockIn,
            identity: ConfirmationMotion.identity(clockInAt: running.locationId, startedAt: running.startTime),
            confirmed: ShiftSignal.isConfirmed(running, now: now, hasSyncError: syncError?.isEmpty == false),
            eventTime: running.startTime,
            ink: .primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenState(presentation, elapsed: elapsed))
    }

    /// The PRIMARY way to end the shift, and still the only silent one.
    ///
    /// This comment used to read "there is no in-app button and there must not be one:
    /// clocking out is a tag tap, and a second path to the same row is how two mechanisms
    /// start disagreeing about somebody's hours". decision-56 supersedes that for this one
    /// action, and the reasoning survives intact rather than being deleted, because it is
    /// exactly WHY the button below is safe: the second path is not silent. A manual stop
    /// sends `manual: true`, the server stamps `manual_close` (and `corrected_at` in the
    /// same update), and every list that shows shifts shows it - forever. The two mechanisms
    /// cannot disagree about somebody's hours without an admin being able to see which one
    /// produced the row. Prevention was never on the table (a worker with a broken tag had
    /// no way to clock out at all); visibility is.
    private func instruction(tint: Color) -> some View {
        VStack(spacing: 16) {
            // Android's HorizontalDivider at 25% ink: the line between "what is happening" and "what to do".
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(height: 1)
                .accessibilityHidden(true)
            Text("Hold your phone to the tag again to finish.")
                .font(.callout)
                .foregroundStyle(tint.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The in-app way to present the same card, for a phone that is already open in the
    /// worker's hand (TapScanner.swift). THE ONE FILLED BUTTON ON THIS SCREEN: everything
    /// else here is a quiet text button or a bordered corrective one. On the field it inverts
    /// against the field (WorkerField): the ink is its fill and the field is its label.
    private var scanButton: some View {
        Button(action: onScan) {
            Label("Scan a tag", systemImage: "wave.3.right")
        }
        .buttonStyle(.workerPrimary)
    }

    /// SECONDARY, and below the tap instruction on purpose: the tag is still the normal way
    /// out. A quiet text button + a confirmation dialog, never a single destructive tap - decision-56
    /// section 4 requires the confirmation on both new paths, and the dialog NAMES the building so
    /// a mis-tap on the wrong phone is caught before it costs somebody an afternoon.
    private var stopButton: some View {
        Button(role: .destructive) { confirmingStop = true } label: {
            Label("Finish shift without a tag", systemImage: "stop.circle")
        }
        .buttonStyle(.workerQuiet)
        .confirmationDialog(Text("Finish your shift at \(running.locationName) now?"),
                            isPresented: $confirmingStop,
                            titleVisibility: .visible) {
            Button("Finish now", role: .destructive, action: onManualStop)
        } message: {
            Text("This ends the shift at this moment and is marked for the office to review. Use the tag when you can.")
        }
    }

    private func noticeCard(_ text: String) -> some View {
        // A CARD, not an alert. SwiftUI will not present an alert and a sheet at once and
        // silently drops one of them, so the old alert could eat the decision-10 resolver
        // on exactly the tap that produced an auto-closed shift. A card cannot collide
        // with anything.
        card(icon: "arrow.triangle.swap", tint: .orange) {
            Text(verbatim: AppLanguage.rerender(text, locale: locale))
                .accessibilityAddTraits(.isStaticText)
            Button("Dismiss", action: onDismissNotice)
                .buttonStyle(.bordered)
        }
    }

    private var resolverCard: some View {
        card(icon: "exclamationmark.triangle.fill", tint: .orange) {
            Text("\(unresolvedCount) unfinished shift(s) need a finish time before they can be paid.")
            // BORDERED, not filled: a corrective action, and the filled one on this screen
            // is already spoken for by the scan button (2026-08-29 UX audit).
            Button("Confirm finish times", action: onResolve)
                .buttonStyle(.bordered)
        }
    }

    /// Said ONCE, as a sentence, never as a modal and never as a nag. A denied permission
    /// is a weaker signal, not a broken app - the screen you are reading is the floor and
    /// it is unaffected.
    private var notificationsOffCard: some View {
        card(icon: "bell.slash", tint: .secondary) {
            Text("Notifications are off, so this phone cannot remind you to clock out. Everything else still works.")
                .font(.footnote)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered)
        }
    }

    /// The collapsed "Next planned assignment" row. The label stays the same even when the first
    /// assignment is the one being worked (Android: no in-progress state on a plan). The row's
    /// expanded flag lives in ScheduleSummary's own @State, so the once-a-minute TimelineView
    /// redraw of this whole screen cannot fold it. THE CARD IS THIS SCREEN'S: ScheduleSummary
    /// brings no surface of its own.
    private var scheduleCard: some View {
        card(icon: "calendar", tint: .secondary) {
            ScheduleSummary(state: schedule, retry: onReloadSchedule)
        }
    }

    /// The escape that is not a gesture - now one tap away instead of printed on the screen. Sign-out
    /// lives one tab away in More and the materials tab is next to it; the sentence says so out loud,
    /// because a worker who believes they are stuck is the failure this whole screen is not allowed to
    /// cause. A labelled disclosure, so it works with VoiceOver and Dynamic Type for free and - unlike
    /// Android's AlertDialog - cannot collide with the resolver sheet.
    private var helpButton: some View {
        DisclosureGroup(isExpanded: $showHelp) {
            Text("Something wrong? Ask what to do — hours, locations and payroll are managed by your admin on the web. You can still request material and sign out from the tabs below.")
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            Text("Shift help")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: WorkerStyle.quietButtonMinHeight, alignment: .leading)
        }
    }

    /// A NEUTRAL card on the field (Android: notice, resolver and notification blocks stay WorkerCards).
    /// It is simply NOT drawn with `onField`: it keeps the phone's appearance and the plain ink, and the
    /// views and buttons inside are the same ones the idle screen shows.
    @ViewBuilder
    private func card(icon: String, tint: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)     // decorative; the text beside it says it
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .workerCard()
        .tint(Color.primary)
    }
}

private extension View {
    /// Draws one piece of the running screen in the FIELD's ink: the ink is its foreground and tint, the
    /// field/ink pair is what a primary or quiet button inverts against, and the scheme is the dark one
    /// (the phone's own on the overdue-neutral field), so semantic colours resolve against the field.
    func onField(ink: Color, field: Color, scheme: ColorScheme) -> some View {
        self
            .foregroundStyle(ink)
            .tint(ink)
            .environment(\.workerField, WorkerField(field: field, ink: ink))
            .environment(\.colorScheme, scheme)
    }
}

/// decision-60 §3: the procedural half of the fun theme, and it REPLACES decision-57's
/// walking silhouettes rather than layering on top of them - four figures marching under a
/// drifting gradient was two competing focal points on a screen whose whole job is one
/// ticking clock. SwiftUI `Canvas` + `TimelineView` only, exactly as before: NO new asset
/// pipeline, no Lottie/Rive, no bundled image or video.
///
/// A slow dark-to-light blue wash, plus three orbs drifting across it. Nothing here is ever
/// the signal - the words above it are - so the screen must still read with this view
/// deleted, and the orbs stay at low opacity behind opaque cards. The phases come from
/// FunShiftAnimation, which is arithmetic and check-covered without a simulator.
private struct BlueDrift: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 0...1 and back, once per cycle - the dark-to-light breath.
            let breath = (FunShiftAnimation.sweepSwing(figure: 0, at: t, period: 18) + 1) / 2
            Canvas { ctx, size in
                let dark = tint.opacity(0.55)
                let light = tint.opacity(0.10)
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: breath < 0.5 ? [dark, light] : [light, dark]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width * breath, y: size.height))
                )
                ctx.opacity = 0.22
                for orb in 0..<FunShiftAnimation.figureCount {
                    let phase = FunShiftAnimation.walkPhase(figure: orb, at: t, cycle: 26)
                    let r = min(size.width, size.height) * (0.18 + 0.05 * Double(orb % 2))
                    let x = phase * (size.width + r * 4) - r * 2
                    let y = size.height * (0.25 + 0.5 * (FunShiftAnimation.sweepSwing(figure: orb, at: t, period: 11) + 1) / 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(tint))
                }
            }
            .blur(radius: 40)      // orbs, not discs - the edges must never read as content
            .drawingGroup()        // one offscreen pass, not four layers composited per frame
        }
    }
}
