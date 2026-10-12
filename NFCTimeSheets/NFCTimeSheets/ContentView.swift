//
//  ContentView.swift
//  NFCTimeSheets
//

import SwiftUI
import SwiftData

// The API layer lives in API.swift, the sync engine in Sync.swift, identity in Auth.swift.
// There is no admin screen here: admin is password-authenticated on the web (decision-20).

/// The whole app is one of two screens, chosen by the server's answer to "who is this?"
/// (decision-22). Sign-in offers SMS and the admin-issued code, both always visible, never
/// gated (decision-50) - there is no third, dead-end screen any more.
struct ContentView: View {
    @Environment(Session.self) private var session
    /// Read here for ONE reason: a tap that arrives while the worker is on Materials or More must
    /// bring them to the Shift tab (Android SignedInScaffold selects the Shift tab, then consumes).
    /// It is never TAKEN here - LogView's take() stays the single consumer, so a tap is still
    /// handled exactly once (checks/tap-inbox-check.swift, shift-signal-check.swift).
    @Environment(TapInbox.self) private var inbox
    /// The selected tab, by name. Three destinations, always (Shift, Materials, More): History is
    /// never one of them, it is a row under More (SettingsView).
    @State private var selection: AppTab = .log
    /// Rows an on-device migration archived, shown once as a receipt. Loaded lazily and
    /// only inside the eligible branch: that branch mounts after the launch task has run
    /// the migrations, so there is no race between "what happened" and "telling them".
    @State private var receipt: [ArchivedShift] = []
    @State private var showReceipt = false
    /// Material requests. Owned HERE and not in NFCTimeSheetsApp on purpose: it is only
    /// needed once the server has said who this is, and it dies on sign-out, which is
    /// exactly the lifetime a queue of one worker's own words should have. It is a plain
    /// observable object over a JSON file - it does NOT touch the SwiftData store that
    /// holds unpushed shifts. See the header of Materials.swift.
    @State private var materials = MaterialStore()
    @State private var locationReporter = ShiftLocationReporter.shared
    /// The lock reads this and nothing else. A separate @Query rather than a value passed
    /// up from LogView: the TAB BAR is what changes, and it is built here.
    ///
    /// DEVICE-WIDE ON PURPOSE, and named so (`allShifts`): it is every account's rows. It is
    /// only ever read through WorkerScope (forWorker / openShift(for:) / completed(for:)) -
    /// checks/worker-scope-check.swift fails on any other use.
    @Query private var allShifts: [Shift]

    /// The lock is the SIGNED-IN worker's: another account's forgotten open row must not
    /// shorten this worker's tab bar.
    private func shiftRunning(for workerId: Int) -> Bool { allShifts.openShift(for: workerId) != nil }

    var body: some View {
        switch session.state {
        case .unknown:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Checking your sign-in")
        case .signedOut(let reason):
            SignInView(reason: reason)
        case .eligible(let worker):
            // THE LOCK. The tab bar is three destinations in EVERY state - Shift, Materials, More
            // - and History is not one of them: it is a row under More that is offered only
            // while no shift runs, because nothing in it is time-critical. Materials and More
            // never go, because a worker standing in a building needs to ask for supplies and
            // a handed-over phone must be signable-out (decision-22). The resolver is not a
            // tab - it is a banner on the Shift tab, present in every state (decision-10).
            //
            // This is WORK DISCIPLINE and not a security boundary: the rule lives in the
            // pure ShiftSignal.visibleTabs, which checks/shift-signal-check.swift asserts
            // can never return a set without Materials and Settings in it.
            //
            // `.id(worker.id)` IS THE RESET. A DIRECT worker change - Session.restore()
            // replacing the cached A with the server's B without ever passing through
            // signed-out - would otherwise keep every tab's @State (the unresolved list, the
            // switch notice, a half-typed material request, an open sheet) and never re-run
            // LogView's refresh. A new identity recreates all three tabs, so B starts from B's
            // own refresh (Android adopt() resets LogState and the schedule for the same
            // reason). It must stay the FIRST modifier: the .task and .sheet below sit
            // OUTSIDE it on purpose, and the materials store is owned above it.
            TabView(selection: $selection) {
                // THREE DESTINATIONS, ALWAYS (Android TimeSheetApp.kt: `visibleTabs(...).filterNot
                // { it == HISTORY }`). ShiftSignal.visibleTabs and AppTab are untouched - the lock's
                // own rule and its check still speak of four - and this is where History stops being
                // a tab: it is a row under More while no shift is open (SettingsView).
                ForEach(ShiftSignal.visibleTabs(shiftRunning: shiftRunning(for: worker.id)).filter { $0 != .history }, id: \.self) { tab in
                    switch tab {
                    case .log:
                        LogView(worker: worker)
                            .tabItem { Label("Shift", systemImage: "clock") }
                            .tag(AppTab.log)
                    case .materials:
                        // The badge counts requests the warehouse has and the worker has
                        // not been told about. There is no push in this system
                        // (decision-23: the server's dependencies are pg + @sentry/node),
                        // so this number only moves when the app is opened, and the
                        // screen says so in words.
                        //
                        // This is the TAB badge. The APP-ICON badge is a different
                        // surface and belongs to the open shift alone - see
                        // ShiftSignalCenter.arm.
                        MaterialsView(worker: worker)
                            .tabItem { Label("Materials", systemImage: "shippingbox") }
                            .badge(materials.unseenArrivalCount)
                            .tag(AppTab.materials)
                    case .history:
                        // Filtered out above and never mounted: History is pushed from More.
                        EmptyView()
                    case .settings:
                        SettingsView(worker: worker)
                            .tabItem { Label("More", systemImage: "ellipsis") }
                            .tag(AppTab.settings)
                    }
                }
            }
            .id(worker.id)
            .environment(materials)
            // SHIFT EVIDENCE (location). Driven from the STORE, strictly after a tap has saved its
            // row, and failure-silent: a denied permission, no GPS or a dead network only change a
            // footnote - nothing here is read by the tap, the sync pass or the signals. Scoped to
            // the SIGNED-IN worker's open row like every other read (WorkerScope): another
            // account's forgotten open shift must never start location collection for this one.
            .task(id: worker.id) {
                locationReporter.beginSession(workerId: worker.id)
                defer { locationReporter.endSession() }
                while !Task.isCancelled {
                    locationReporter.configure(shift: allShifts.openShift(for: worker.id))
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .onChange(of: allShifts.openShift(for: worker.id)?.clientUuid) { _, _ in
                locationReporter.configure(shift: allShifts.openShift(for: worker.id))
            }
            // At LAUNCH, not when the Materials tab is opened: the badge is the only
            // thing telling a worker something is waiting for them at the warehouse, and
            // a badge that only appears once you have looked is not a badge. Its own
            // task, so a slow or missing materials API cannot delay the Log tab.
            .task(id: worker.id) { await materials.start(workerId: worker.id) }
            // Four rows must not vanish between launches without a word. If the archive
            // is empty there is nothing to report, so the flag is simply cleared.
            .task {
                guard MigrationReceipt.unseen else { return }
                receipt = MigrationReceipt.archived()
                if receipt.isEmpty { MigrationReceipt.unseen = false } else { showReceipt = true }
            }
            .sheet(isPresented: $showReceipt, onDismiss: { MigrationReceipt.unseen = false }) {
                MigrationReceiptSheet(shifts: receipt)
            }
            // A NEW IDENTITY STARTS ON THE SHIFT TAB (a worker who signed out on More must not hand
            // the next one a phone that opens there), and so does a TAP: whatever tab the worker is
            // on, an arriving tap selects Shift. Only the SELECTION moves here - the id is read from
            // the closure, never taken, so LogView's `take()` is still the one thing that handles it.
            .onChange(of: worker.id, initial: true) { _, _ in selection = .log }
            .onChange(of: inbox.pendingLocationId) { _, id in
                if id != nil { selection = .log }
            }
        }
    }
}

// MARK: - State (a): signed out

/// Two doors: an SMS one-time code, and the admin-issued enrolment code. ONE FORM SERVES
/// BOTH (decision-54 §5) - see CodeSignInSection.swift, which the operator gate uses too.
///
/// THE SMS DOOR IS CAPABILITIES-GATED (decision-59 §2), which STRIKES decision-50 §1's
/// "no `GET /auth/capabilities` check here, unlike Android". That rule reasoned that with
/// Apple gone, hiding SMS could leave a phone with exactly one door. The owner accepted
/// that consequence explicitly for THIS flag: `sms_login` exists for controlled testing
/// windows, and every phone in one has an admin a phone call away who can issue an
/// enrolment code on demand. One rule now - capabilities decides visibility - on every
/// platform, with no iOS carve-out to remember.
struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    /// Why the last attempt failed, if it did. Screen-level only (e.g. a dropped
    /// session) - the field-level SMS/code errors below are local @State.
    let reason: String?
    /// FALSE UNTIL THE SERVER SAYS OTHERWISE, and false again the moment it says so. The
    /// initial value is the fail-closed one, so the first frame - drawn before any request
    /// can possibly have returned - never flashes a door that is shut.
    @State private var smsAvailable = false
    /// THE PHONE'S OUTBOX, device-wide: signing out deletes nothing, so a worker who signed out with
    /// unsent shifts must see that the phone still holds them (decision-82, Android TimeSheetApp
    /// SignInScreen). Read through WorkerScope.deviceWide - the only legitimate unscoped read - and
    /// used for nothing but the delivery summary below.
    @Query private var allShifts: [Shift]
    private var deliveryRows: [PendingRow] { allShifts.deviceWide().map { $0.deliveryRow() } }

    var body: some View {
        // OperatorHomeScreen is pushed from operatorSection below, so whatever presents
        // this view needs a NavigationStack ancestor - Settings already has one; this is
        // the second, and now the ONLY one that does not require a worker session first.
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        // THE REAL COMPANY MARK, not a generic radio-waves glyph. It is
                        // achromatic by nature (docs/brand/DESIGN.md measured the source
                        // pixels) - there is no colour version to reach for, and none is
                        // invented here.
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 72)
                            .accessibilityHidden(true)
                        Text("NFC TimeSheets")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Sign in to log your hours.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let reason {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                // What the phone still holds (decision-82): nothing at all when it holds nothing.
                // `signedOut: true` puts the sign-in sentence in the sheet, never "open the app".
                DeliveryStatusRows(rows: deliveryRows, signedOut: true)

                // The phone field, the Request-SMS button, ONE code field and ONE submit
                // button - the same view the operator gate mounts (decision-54 §5). All
                // three calls stay Session's; this view kept no auth state of its own
                // when it consolidated.
                CodeSignInSection(role: .worker,
                                  smsAvailable: smsAvailable,
                                  busy: session.busy,
                                  requestSms: { try await session.requestSmsCode(phone: $0) },
                                  verifySms: { try await session.verifySmsCode(phone: $0, code: $1) },
                                  submitCode: { try await session.signInWithCode($0) })
                operatorSection
            }
            .scrollDismissesKeyboard(.interactively)
            // EVERY APPEARANCE AND EVERY RESUME, not once per process (decision-59 §2,
            // and the same reasoning TASK-276 applied to the operator gate). Android reads
            // this at launch because its sign-in screen IS the launch screen; on iOS this
            // view is pushed and popped, so a launch-only read would mean flipping the flag
            // server-side did nothing until the worker force-quit the app. No spinner and
            // nothing waits on it: the code field is already usable while it is in flight.
            .task { smsAvailable = await AuthAPI.smsDoorAvailable() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { smsAvailable = await AuthAPI.smsDoorAvailable() }
            }
        }
    }

    // MARK: Operator door
    //
    // decision-45 makes an operator a genuinely separate identity from a worker - it must
    // not require signing in as a worker first. Before this, the ONLY route in was
    // Settings, which only exists inside .eligible(worker): a phone that is operator-only
    // had no way in at all (found 2026-08-24, TASK-252).
    //
    // ONE LINK INTO A GATE, not two direct links (decision-54 §4). This reverses what the
    // comment here used to say: the two-direct-link design let anyone with the app
    // installed SEE the operator interface, and gated only the action, inside each screen.
    // decision-54 gates reaching it at all, so OperatorHomeScreen.swift is the retired
    // OperatorSignInScreen back in substance, and WriteTagScreen/VerifyZoneScreen no
    // longer carry a code field of their own. Settings keeps its own identical link for a
    // phone that is already signed in as a worker and also mounts tags.
    private var operatorSection: some View {
        Section {
            NavigationLink("Write or test tags") { OperatorHomeScreen() }
        } footer: {
            Text("Operator? Write or test tags without signing in as a worker.")
                .font(.footnote)
        }
    }

    // The SMS door, the enrolment-code door and every per-outcome error sentence they
    // showed all moved, verbatim, into CodeSignInSection.swift - nothing was dropped in
    // the move, only the LAYOUT consolidated (decision-54 §5).
}

// MARK: - Log tab

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(TapInbox.self) private var inbox
    /// Who the SERVER says is holding this phone. Not a preference, not editable, and
    /// never sent in a shift body - it is here to stamp local rows and to keep another
    /// account's queued rows from being pushed under this session (decision-22).
    let worker: WireWorker
    /// Asked after an `await`, before anything is published or armed: is `worker` still the one
    /// holding the session? (WorkerScope.isCurrent)
    @Environment(Session.self) private var session
    /// EVERY ACCOUNT'S ROWS, newest first - the phone's outbox. Never read directly: this
    /// screen shows and toggles only the signed-in worker's rows (WorkerScope.swift), and
    /// checks/worker-scope-check.swift fails on any use of `allShifts` that does not go
    /// through forWorker / openShift(for:) / completed(for:).
    @Query(sort: \Shift.startTime, order: .reverse) private var allShifts: [Shift]
    @Query private var sites: [Site]
    @Environment(ShiftSignalCenter.self) private var signals
    @Environment(RosterZones.self) private var rosterZones
    @Environment(\.scenePhase) private var scenePhase
    /// "Your open shift at A was finished and one at B was started." A CARD, not an
    /// alert: SwiftUI silently drops one of an alert and a sheet presented together, so
    /// the old alert could eat the decision-10 resolver on exactly the tap that created
    /// an auto-closed shift. Android has always shown this as a card; this is iOS
    /// catching up (parity row 9).
    @State private var switchNotice: String?
    @State private var unresolved: [WireShift] = []
    @State private var showResolver = false
    /// decision-56: the building picked in the "start without a tag" sheet, and whether the
    /// confirmation for it is up. Two pieces of state, not one, because the pick is not the
    /// decision - nothing is posted until the dialog is confirmed.
    @State private var showManualStart = false
    @State private var manualPick: String?
    @State private var confirmingManualStart = false
    /// decision-81: a request is in flight / the server's last refusal, shown inside the sheet.
    @State private var manualBusy = false
    @State private var manualError: String?
    /// The foreground scan (TapScanner.swift). One instance for the life of the view, and
    /// `scanError` is the calm sentence for a card that could not be read or is not ours -
    /// never a crash, never a silent no-op.
    @State private var scanner = TapScanner()
    @State private var scanError: String?
    @State private var scanning = false
    /// decision-80: the worker's PLANNED assignments, for the two schedule rows and nothing else.
    /// Held HERE so the idle list and the running screen show one answer, and so it dies with this
    /// view: on sign-out, on a 401 and (through `.id(worker.id)` on the TabView) on a change of
    /// worker. DISPLAY ONLY - nothing on the tap path, in `refresh()`, in the sync pass or in the
    /// signals reads it, and `loadSchedule()` is its one trigger (see ScheduleStore.swift).
    @State private var schedule = ScheduleStore()
    /// SHIFT EVIDENCE (photo proof, docs/shift-evidence.md). Only ever set for a FINISH whose shift
    /// is KNOWN to require proof (`proofOfWorkRequired == true`, see prepareCompletion); a start, a
    /// finish of a proof-disabled shift and a finish whose policy this phone does not know are never
    /// held back by any of it. `closePending` is true exactly while the proof sheet is up or its
    /// upload and close are in flight - it dies with this view like every other @State here.
    @State private var proofShift: Shift?
    @State private var closePending = false
    @State private var afterProof: (() -> Void)?
    @State private var proofCompleting = false
    @State private var proofManualClose = false
    @State private var proofAutoClose = false
    /// decision-82: bumped when a held-back delivery row settles, so `deliveryRows` is read again.
    @State private var deliveryTick = 0
    /// decision-83 (P7): which finished shift the idle list is offering a "Shift finished" receipt
    /// for, and which one the worker dismissed. A VALUE (ShiftReceipt.Memory): the rule - offered
    /// when the newest finish is 0-120 s old, then kept until Continue - runs on a Mac in
    /// checks/shift-receipt-check.swift. DISPLAY ONLY: nothing on the tap path, in the sync pass or
    /// in the signals reads it, and it dies with this view like every other @State here.
    @State private var receiptMemory = ShiftReceipt.Memory()

    /// The row a tap toggles and the running screen shows: THIS worker's newest open row. Another
    /// account's forgotten open row is not it (WorkerScope.openShift) - B's first tap must start
    /// B's shift, not close A's.
    private var openRow: Shift? { allShifts.openShift(for: worker.id) }
    private var recent: [Shift] { Array(allShifts.completed(for: worker.id).prefix(5)) }
    /// decision-83: the finished shift whose receipt is up, or nil. It is the NEWEST finished row of
    /// THIS worker (`recent.first`), and only while the memory offers it - derived in the same
    /// render, so the first frame after a finish already shows the receipt and never the start
    /// controls first.
    private var receiptShift: Shift? {
        guard let latest = recent.first,
              receiptMemory.offer(for: latest.receiptIdentity, now: .now) != nil else { return nil }
        return latest
    }
    /// Recent, minus the row the receipt is showing (Android: `filterNot { showReceipt && it == latest }`).
    private var recentRows: [Shift] {
        guard let shown = receiptShift else { return recent }
        return recent.filter { $0.clientUuid != shown.clientUuid }
    }
    /// What the PHONE still holds, for every account that queued it (decision-82): the one deliberate
    /// device-wide read on this screen. It feeds the delivery rows on the idle list and the running
    /// screen and nothing else - never a list, a total, the lock or a tap.
    private var phoneRows: [PendingRow] {
        allShifts.deviceWide().map { $0.deliveryRow(sessionWorkerId: worker.id) }
    }
    /// The same, minus a tap's own request that has not been answered yet (PendingWork.settleGrace), so a
    /// normal online clock-in or clock-out never pops a "waiting" row in and out. `deliveryTick` is bumped
    /// by the task below at the moment the earliest held-back row stops being held back.
    private var deliveryRows: [PendingRow] {
        _ = deliveryTick
        return PendingWork.settled(phoneRows, now: .now)
    }
    private var deliverySettleAt: Date? { PendingWork.nextSettle(phoneRows, now: .now) }

    /// The ONE value the shift screen and every out-of-app signal are derived from
    /// (ShiftSignal.swift). Built from the LOCAL row, because a tap in a basement has one
    /// and a server response may never arrive.
    private var running: RunningShift? {
        openRow.map(asRunning)
    }

    /// The same value, read straight out of the context instead of out of `@Query`.
    ///
    /// This is what the SIGNAL is armed from, and the distinction matters: `@Query`
    /// republishes on SwiftData's own schedule, so reading it in the same turn as the
    /// `context.save()` that just wrote a row can hand back the state from BEFORE the tap.
    /// A fetch cannot. Rendering may lag a frame; a badge that says "clocked in" after a
    /// clock-out may not.
    ///
    /// SCOPED TO THE SESSION'S WORKER, like everything else here: the badge, the reminder
    /// ladder and the Live Activity are armed from this, so an unscoped read would arm worker
    /// B's phone with worker A's leftover shift.
    private func currentRunning() -> RunningShift? {
        let all = (try? context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\Shift.startTime, order: .reverse)]))) ?? []
        return all.openShift(for: worker.id).map(asRunning)
    }

    /// Re-arm from the store AFTER an `await`, but only while `worker` still holds the session.
    /// A refresh started for A that lands after A signed out (the teardown in Session already
    /// ran) or after B replaced A must not put A's badge back. Not used right after a local
    /// write - there is no await in between there, and a tap is never gated on anything.
    private func armIfStillCurrent() {
        guard WorkerScope.isCurrent(worker.id, session: session.worker?.id) else { return }
        signals.arm(for: currentRunning())
    }

    private func asRunning(_ shift: Shift) -> RunningShift {
        RunningShift(locationId: shift.locationId,
                     locationName: siteName(shift.locationId),
                     startTime: shift.startTime,
                     // decision-10: the server flagged it and no human has fixed it. The
                     // screen must then stop showing a running clock.
                     serverAutoClosed: shift.autoClosed && shift.correctedAt == nil,
                     // PRESENTATION ONLY: the start exists only on this phone until the
                     // server has acknowledged it (Sync.pushOpen sets openSyncedAt). It picks
                     // words - the screen's heading and the reminders' text - and nothing else.
                     pendingConfirmation: shift.openSyncedAt == nil)
    }
    /// "Unknown location" until the roster arrives, and that is fine: a missing name is
    /// cosmetic, a missing shift is unpaid work. Nothing branches on this string.
    ///
    /// A shift row keeps the id that was TAPPED, which is a zone id for every zone card, so the
    /// name is the zone's BUILDING (decision-43) - see Zones.buildingName.
    private func siteName(_ id: String) -> String {
        rosterZones.buildingName(of: id, sites: sites) ?? String(localized: "Unknown location")
    }

    var body: some View {
        // decision-80: the schedule is asked for every time this tab appears (a return from
        // another tab, the first appearance). It sits on the NavigationStack and not on the Group
        // inside it, because that Group swaps between the idle list and the running screen, and
        // starting or finishing a shift is not a reason to ask again. A return to the foreground
        // is the other trigger (the scenePhase handler below); a retry is the third.
        content
            .onAppear { loadSchedule() }
    }

    private var navigationTitle: LocalizedStringKey {
        running == nil ? "" : "Shift running"
    }

    private var content: some View {
        NavigationStack {
            // TWO SHAPES, and which one is on screen is the entire point of this work.
            // Idle: a list of recent shifts with a hint at the bottom. Running: a
            // full-bleed screen with a ticking clock, which is unmistakable from across
            // a room. The old build's whole in-shift signal was an orange pill on a row.
            Group {
                if let running {
                    ShiftScreen(running: running,
                                unresolvedCount: unresolved.count,
                                onResolve: { showResolver = true },
                                notice: switchNotice,
                                onDismissNotice: { switchNotice = nil },
                                onManualStop: manualStop,
                                onScan: scan,
                                deliveryRows: deliveryRows,
                                syncError: openRow?.syncError,
                                syncBlocked: openRow?.syncBlocked ?? false,
                                onRefresh: { Task { await refresh() } },
                                schedule: schedule.state,
                                onReloadSchedule: loadSchedule)
                } else {
                    idleList
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = ShiftLocationReporter.shared.message {
                    Text(message).font(.footnote).padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            // The idle screen has its own heading (today's date and "Your working day", the first row of
            // the list), so its navigation title is EMPTY and inline: Android's worker screens have no top
            // app bar either. The bar itself stays (an empty inline bar draws nothing) because it is what
            // gives a scrolling list its edge treatment under the status bar. The running screen keeps its
            // title until the running reskin (TASK-365.11) takes it away. A LocalizedStringKey, not a
            // ternary of two literals, so the running title is looked up in the catalogue (TASK-298).
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(running == nil ? .inline : .large)
            .refreshable { await refresh() }
            // THE IN-APP SCAN IS BACK, and on NFCTagReaderSession, not the retired
            // NFCNDEFReaderSession: `NDEF` in com.apple.developer.nfc.readersession.formats
            // is App Store error 90778, `TAG` is what this app already has, and that is what
            // TapScanner uses. It exists because the background tap opens a universal link
            // and iOS shows a system transition for it even when the app is already open in
            // the worker's hand - confusing exactly where it should be calmest.
            //
            // It adds NO clock-in logic: a resolved tag goes to `inbox.accept`, the same
            // mailbox onOpenURL/onContinueUserActivity post into, and comes back out through
            // the onChange below into the one handleTap.
            .alert("Couldn't read that tag",
                   isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
                Button("OK") { scanError = nil }
            } message: {
                Text(scanError ?? "")
            }
            .onChange(of: inbox.pendingLocationId) { _, id in
                guard id != nil, let tapped = inbox.take() else { return }
                handleTap(tapped)
            }
            .task {
                if let pending = inbox.take() { handleTap(pending) }  // tap that launched the app
                await signals.refreshAuthorization()
                await refresh()
            }
            // decision-82: wakes the delivery rows when the earliest in-flight tap has been unanswered for
            // the grace. Display only: it sleeps, bumps a counter, and nothing on the tap path reads it.
            .task(id: deliverySettleAt) {
                guard let settleAt = deliverySettleAt else { return }
                let wait = settleAt.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if !Task.isCancelled { deliveryTick += 1 }
            }
            // onDismiss, not just on present: confirming an auto-closed shift is the one
            // path that can end a shift WITHOUT a tag tap, and a lock screen or a badge
            // left standing after it would be exactly the "stuck lock / orphaned
            // notification" this work exists to prevent.
            .sheet(isPresented: $showResolver, onDismiss: { signals.arm(for: currentRunning()) }) {
                ResolveSheet(shifts: $unresolved, siteName: siteName)
            }
            .sheet(isPresented: $showManualStart) { manualStartSheet }
            .sheet(item: $proofShift, onDismiss: { if !proofCompleting { closePending = false; afterProof = nil } }) { shift in
                ShiftProofSheet(clientUuid: shift.clientUuidString) { proofId in
                    guard shift.isOpen else { return }
                    shift.proofId = proofId
                    shift.pendingEvidenceEnd = .now
                    shift.pendingEvidenceManual = proofManualClose
                    shift.pendingEvidenceAuto = proofAutoClose
                    try? context.save()
                    proofCompleting = true
                    Task {
                        defer { proofCompleting = false }
                        do {
                            DeliveryAttempt.stamp()   // a request is about to leave this phone (decision-82: "Last attempt")
                            shift.lastAttemptAt = .now
                            let response = try await ShiftAPI.close(clientUuid: shift.clientUuidString, endTime: shift.pendingEvidenceEnd ?? .now,
                                autoClosed: proofAutoClose, manual: proofManualClose, proofId: proofId)
                            guard case .eligible(let signedIn) = session.state, signedIn.id == worker.id else { return }
                            let action = afterProof
                            afterProof = nil
                            closePending = false
                            action?()
                            shift.endTime = response.shift.endTime
                            shift.autoClosed = response.shift.autoClosed
                            shift.correctedAt = response.shift.correctedAt
                            shift.pendingEvidenceEnd = nil
                            shift.syncError = nil
                            shift.syncBlocked = false
                            shift.closeSyncedAt = .now
                            try? context.save()
                        } catch {
                            scanError = String(localized: "Could not finish the shift. Check your connection and try again.")
                            closePending = false
                        }
                    }
                }
            }
            // Coming back from the background is the only chance to re-arm a Live Activity
            // the worker dismissed by hand, or to notice that notifications were switched
            // on (or off) in Settings while the app was not running.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                signals.arm(for: currentRunning())
                Task { await signals.refreshAuthorization() }
                // A zone created while the app was in the background is not in the cache yet.
                // Silent on failure, never awaited before the arm above, never a gate on a
                // tap. Re-armed afterwards so the fixed-text reminders carry the real name.
                Task {
                    await refreshRoster(context: context)
                    armIfStillCurrent()
                }
                // decision-80: last, and not awaited - the plan is a picture, never a reason to
                // hold the arm or the roster pass back.
                loadSchedule()
            }
        }
    }

    /// decision-80. Ask the server for THIS worker's plan. Returns at once: the request is its own
    /// Task inside the store, concurrent with and never inside `refresh()` / the sync pass, and
    /// nothing on the tap path calls this. The session is asked again after the await, so an
    /// answer for a worker who has since signed out or been replaced is dropped.
    private func loadSchedule() {
        let session = session
        schedule.load(for: worker.id) { session.worker?.id }
    }

    /// The app with no shift running, in the order a cleaner checking the phone at a door reads it
    /// (Android TimeSheetApp.kt LogScreen at 60f6886): today's date and "Your working day", the
    /// unresolved banner, then ONE focused block - the receipt of the shift just finished, or the
    /// start card - then what the phone still holds, the next planned assignment and Recent.
    /// The action is FIRST; the history of the day follows it.
    ///
    /// A List still, and not a ScrollView of cards: pull-to-refresh is the refresh control (there is
    /// no Refresh button here, as there is on Android) and History shares the row shape. Every row
    /// is chrome-free (`workerListRow`) and the cards inside it are the surfaces.
    private var idleList: some View {
        List {
            WorkerDayHeading()
                .workerListRow()
            if !unresolved.isEmpty {
                Button { showResolver = true } label: {
                    Label("\(unresolved.count) unfinished shift(s) need a finish time",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .workerCard()
                .workerListRow()
            }
            // decision-83: the "Shift finished" receipt takes the start card's place (Android replaces
            // its start card with it). Inline, never a sheet or alert: taps, tabs and the resolver keep
            // working. Its row is filtered out of Recent below.
            if let receiptShift {
                ShiftReceiptView(shift: receiptShift, name: siteName(receiptShift.locationId)) {
                    receiptMemory.dismiss(receiptShift.receiptIdentity)
                }
                .workerListRow()
            }
            // decision-83: the scan block and "Start without a tag" are the start card the receipt
            // replaces (Android). A tag tap still starts a shift; Continue brings these back.
            //
            // ONE block: a mark, the question, the hint, the one filled button and a quiet manual start.
            // decision-56 §4: the manual start stays CLEARLY SECONDARY - a plain text button under the
            // tap, never a second filled one - and it is a normal worker action, not a fallback mode.
            // It is still flagged, never silent: the sheet it opens says so before anything is posted
            // and the confirmation dialog says so again.
            if receiptShift == nil {
                VStack(spacing: 16) {
                    WorkerGlyph(systemName: "iphone.radiowaves.left.and.right")
                    Text("Ready for your shift?")
                        .font(WorkerStyle.Typeface.lead)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Hold your phone to the tag by the entrance to start.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    // THE ONE FILLED BUTTON on this screen: the primary action.
                    Button(action: scan) {
                        Label("Scan a tag", systemImage: "wave.3.right")
                    }
                    .buttonStyle(.workerPrimary)
                    Button("Start without a tag") {
                        manualPick = nil
                        manualError = nil
                        showManualStart = true
                    }
                    .buttonStyle(.workerQuiet)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .workerListRow()
            }
            // decision-82: what the phone still holds - blocked and waiting count rows, nothing at all
            // when the outbox is empty. Not wrapped in a Section on purpose: an empty Section would
            // still draw a gap on the screen most workers see most of the time.
            DeliveryStatusRows(rows: deliveryRows, signedOut: false)
                .workerListRow()
            // decision-80: the collapsed "Next planned assignment" row, after the start card and above
            // Recent (Android: after the delivery rows, before "Zuletzt").
            ScheduleSummary(state: schedule.state, retry: loadSchedule)
                .workerCard()
                .workerListRow()
            // decision-83: while the receipt shows the only finished row, a "Recent" header over
            // nothing (or over "No completed shifts yet.") would contradict the screen.
            if receiptShift == nil || !recentRows.isEmpty {
                Section("Recent") {
                    if recent.isEmpty {
                        Text("No completed shifts yet.")
                            .foregroundStyle(.secondary)
                            .workerListRow()
                    }
                    ForEach(recentRows) { ShiftRow(shift: $0, name: siteName($0.locationId)) }
                }
                .headerProminence(.increased)
            }
            #if DEBUG
            manualMockSection
            #endif
            // Android has said this out loud since day one and iOS only had it as a
            // code comment (parity row 20). Promising a notification to somebody who
            // then does not get one is the difference between a late delivery and a
            // broken product.
            Text("This app has no push. Everything you see here updates when you open it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .workerListRow()
        }
        .workerListPage()
        // Blue Hour is monochrome chrome: the text buttons inside the cards (the plan's "View", "Try again",
        // the delivery rows) are the ink, like Android's TextButtons in onSurface, and the one coloured
        // control on this screen is the red of a blocked delivery row (it sets its own .tint(.red)).
        .tint(.primary)
        // decision-83: remember the offer, so a receipt entered within two minutes outlives the
        // window and stays until Continue. `initial: true` is the first appearance after a finish.
        // It only records which receipt was shown; the screen above already derived it.
        .onChange(of: recent.first?.receiptIdentity, initial: true) { _, latest in
            receiptMemory.observe(latest, now: .now)
        }
    }

    /// decision-81: the picker lists ZONES (cached roster zones whose building is cached), never
    /// buildings - a building id is no clock-in target since decision-69, so a manual start
    /// posted with one was refused 422 in the background behind a normal-looking running
    /// screen. An empty list is a real state on a fresh install with no signal, so it says so
    /// instead of showing an empty wheel above a live Start button.
    private var manualStartSheet: some View {
        NavigationStack {
            Form {
                if manualPlaces.isEmpty {
                    Text("No zones are available. Please refresh first. If your zone is still missing, contact the office.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("Zone", selection: $manualPick) {
                        // Always present, always first, for the same reason BuildingPicker
                        // has one: a nil selection with no matching tag renders BLANK, which
                        // reads as a broken control rather than an unanswered question.
                        Text("Choose a zone").tag(String?.none)
                        ForEach(manualPlaces) { place in
                            Text(place.label).tag(String?.some(place.zoneId))
                        }
                    }
                    Text("Only use this when the tag is missing or cannot be read. Pick the zone in the building you are working in now. The shift is flagged for the office as a manual start.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                // The server's refusal, in the worker's words, right where they are looking.
                // The sheet stays open and nothing was written.
                if let manualError {
                    Text(manualError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel(manualError)
                }
            }
            .navigationTitle("Start without a tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showManualStart = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { confirmingManualStart = true }
                        .disabled(manualPick == nil || manualBusy)
                }
            }
            .confirmationDialog(Text("Start a shift at \(manualLabel(manualPick))?"),
                                isPresented: $confirmingManualStart,
                                titleVisibility: .visible) {
                Button("Start shift") { startManual() }
            } message: {
                Text("The clock starts now and this is marked for the office to review. Use the tag when you can.")
            }
        }
    }

    /// The cached zones, plus - only while a debug mock is armed - one mock zone built from the
    /// canned building, so the picker is walkable on a simulator that can reach no server.
    /// Never written to the SwiftData cache; see ShiftMockFlows.swift.
    private var manualPlaces: [ManualStart.Place] {
        var places = ManualStart.places(
            zones: rosterZones.zones,
            buildingNames: Dictionary(sites.map { ($0.locationId, $0.name) }, uniquingKeysWith: { first, _ in first }))
        #if DEBUG
        if ShiftMocks.active != nil, let building = ShiftMocks.locations.first {
            places.append(ManualStart.Place(zoneId: "99999999-9999-4999-8999-999999999999",
                                            buildingName: building.name, zoneName: "Haupteingang (mock)"))
        }
        #endif
        return places
    }

    private func manualLabel(_ zoneId: String?) -> String {
        manualPlaces.first { $0.zoneId == zoneId }?.label ?? ""
    }

    /// decision-81. ASK THE SERVER FIRST, then write. The zone id is posted with `manual: true`
    /// under ONE client_uuid and ONE start time fixed here, before the request:
    ///   - accepted           -> the same local-first `handleTap` a tag uses writes the row (the
    ///                           sync pass re-posts the same client_uuid and gets 200 duplicate);
    ///   - refused (4xx)      -> shown in the sheet in the worker's words, NO row, sheet stays;
    ///   - could not be asked -> the same `handleTap`, same client_uuid: a manual start still
    ///                           works in a basement, and the queue retry cannot open it twice.
    /// An already-open shift is answered inline without a request (Android manualOpen).
    private func startManual() {
        guard let zoneId = manualPick, !manualBusy else { return }
        // THIS worker's open shift. Another account's forgotten row is not a reason to refuse
        // (the server holds one open shift per WORKER, decision-19), and a refusal here would
        // lock B out of manual start behind A's shift.
        if openRow != nil {
            manualError = APIFailure(status: 409, code: "shift_already_open").workerMessage
            return
        }
        manualError = nil
        manualBusy = true
        let clientUuid = UUID()
        let start = Date.now
        Task {
            defer { manualBusy = false }
            do {
                _ = try await ShiftFlowAPI.open(clientUuid: clientUuid.uuidString.lowercased(),
                                                locationId: zoneId, startTime: start, manual: true)
                showManualStart = false
                handleTap(zoneId, manual: true, clientUuid: clientUuid, startTime: start)
            } catch let failure as APIFailure {
                switch ManualStart.classify(failure) {
                case .refuse:
                    manualError = failure.workerMessage
                    Telemetry.log("manual start refused", .info, [
                        "ts.api.status": failure.status,
                        "ts.api.code": failure.code,
                        "ts.location.id": zoneId,
                    ])
                case .queue:
                    showManualStart = false
                    handleTap(zoneId, manual: true, clientUuid: clientUuid, startTime: start)
                }
            } catch {
                showManualStart = false
                handleTap(zoneId, manual: true, clientUuid: clientUuid, startTime: start)
            }
        }
    }

    /// decision-56 §4/§3. Closes the LOCAL row first, exactly as a tap-out does, so a Stop
    /// pressed in a basement still counts; `manualClose` rides up with the queued close.
    /// `autoClosed` is deliberately left alone: this is a worker confirming their own finish
    /// time in the moment, not the 8h timer guessing, so it must not enter the decision-10
    /// resolver - the server stamps corrected_at instead.
    private func manualStop() {
        prepareCompletion(manual: true) { finishManualStop() }
    }

    /// SHIFT EVIDENCE (docs/shift-evidence.md): the ONE gate in front of a FINISH - a manual stop, a
    /// tag tap-out, a building switch. It holds a finish back for exactly one reason: THIS worker's
    /// open row is KNOWN to require photo proof (`proofOfWorkRequired == true`, learned from the
    /// server's own answer to the open), because the server refuses a close without one. Then the
    /// proof sheet runs first and `action` follows the server's acceptance.
    ///
    /// EVERYTHING ELSE RUNS `action` AT ONCE, in this same turn, with nothing awaited: proof not
    /// required, and - the case that matters in a basement - policy NOT KNOWN YET (a shift opened
    /// offline, or a row from before this build). The tap is never refused for want of a connection
    /// and nothing waits on the network before the local write (audit R2). If the server turns out to
    /// require proof it answers 422 proof_required to the queued close; Sync.record reopens the row,
    /// remembers the policy, and says why, and the next stop opens the camera. A START is never
    /// routed through here at all.
    private func prepareCompletion(manual: Bool = false, switched: Bool = false, _ action: @escaping () -> Void) {
        // A finish is already waiting on the camera or its upload: this tap is the same intent.
        guard !closePending else { return }
        guard let shift = openRow, shift.proofOfWorkRequired == true else {
            action()
            return
        }
        closePending = true
        proofManualClose = manual
        proofAutoClose = switched
        afterProof = action
        proofShift = shift
    }

    /// The close itself: the LOCAL row first (the old manualStop body, unchanged).
    private func finishManualStop() {
        guard let running = openRow else { return }
        running.endTime = .now
        running.manualClose = true
        running.closeSyncedAt = nil
        try? context.save()
        // AFTER the save, never before it - same ordering rule as handleTap.
        signals.arm(for: currentRunning())
        Telemetry.log("manual clock-out", .info, [
            "ts.location.id": running.locationId,
            "ts.shift.client_uuid": running.clientUuidString,
        ])
        Task {
            await syncPending(context: context, workerId: worker.id)
            // Once the push has answered, state the world again. A stop has nothing left to
            // word differently (the shift is closed, so this arms nothing), but it is the same
            // rule as a tap's: every push is followed by one arm from the store, so the signals
            // never disagree with the row the server has just acknowledged.
            armIfStillCurrent()
        }
    }

    #if DEBUG
    /// Absent from a Release build, byte for byte - see ShiftMockFlows.swift. It ARMS the
    /// canned responses and nothing else: the worker then presses the shipping "Start without
    /// a tag" and the shipping Stop, so what is walked is this file's real code.
    @ViewBuilder
    private var manualMockSection: some View {
        Section {
            ForEach(ShiftMockFlow.allCases) { flow in
                Button(flow.label) { ShiftMocks.arm(flow) }
            }
            Button("Mock: off") { ShiftMocks.arm(nil) }
        } header: {
            Text("Simulate (debug builds only)")
        } footer: {
            Text("No network. Arms canned /shifts responses; the buttons above stay the real ones.")
        }
    }
    #endif

    /// The foreground scan. Resolves a card in-app and posts it to the SAME TapInbox the
    /// background universal link posts into - so every open/close decision still happens in
    /// exactly one place, `handleTap`, reached through the `.onChange` above.
    ///
    /// Every non-resolving outcome ends in a sentence or in silence, never in a no-op the
    /// worker cannot explain: a cancelled sheet says nothing (they cancelled it), anything
    /// else says why.
    private func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            defer { scanning = false }
            switch await scanner.scan() {
            case .resolved(let locationId):
                inbox.accept(locationId)
            case .unrecognised:
                scanError = String(localized: "This card isn't one of ours. Ask your admin to check it.")
            case .failed(let message):
                scanError = message
            }
        }
    }

    private func refresh() async {
        await refreshRoster(context: context)
        await refreshFlags()     // decision-57: same pass as the roster, never blocking
        await adoptServerOpenShift(context: context)
        await syncPending(context: context, workerId: worker.id)
        unresolved = await fetchUnresolved()
        // THE RECOVERY HALF OF THE ONE WIRE (audit §4). adoptServerOpenShift may have just
        // learned about a shift this phone had never heard of - reinstall, new device, or
        // a tap that opened the shift before the local row landed - and the badge, the
        // ladder and the Live Activity have to come back from exactly the same call the
        // tap path uses. `running` is recomputed from the store, so a shift the server
        // closed in the meantime arms nothing at all.
        //
        // Guarded on the session worker being STILL this worker (WorkerScope.isCurrent): this
        // function awaits five network calls, and a sign-out or a worker change can land in
        // the middle of them - Session's teardown must not be undone by a stale refresh.
        armIfStillCurrent()
    }

    /// One tap = one toggle. The row is written locally first (so a tap in a basement
    /// still counts) and pushed straight after.
    ///
    /// A TAP ALWAYS PRODUCES A ROW. There is no longer any branch that returns without
    /// writing one, and there must never be one again.
    ///
    /// DELETED: `guard sites.contains(where: { $0.locationId == locationId })`, which
    /// refused the tap when the LOCAL roster cache did not know the location. That was
    /// the wrong invariant and it broke the product: `sites` is filled by refreshRoster(),
    /// which needs the network, and on a tag-tap cold launch onOpenURL delivers the id
    /// before any roster fetch has finished - so on a fresh install a perfectly valid tag
    /// was refused as unknown and the worker lost paid time standing at the door.
    /// The SERVER is authoritative for whether a location exists (decision-19): POST
    /// /shifts/open runs validate.js activeLocation and answers 422 unknown_location,
    /// which APIFailure classifies as terminal, which Sync.record turns into syncBlocked +
    /// "This location was removed. Ask your admin.", which ShiftRow.syncStatus already
    /// renders in red. That rejection path exists end to end; the guard only pre-empted it
    /// with a worse answer. A missing NAME is cosmetic (siteName falls back below); a
    /// missing SHIFT is unpaid work.
    ///
    /// `manual` (decision-56) changes exactly one thing: the flag stamped on a row this
    /// function was going to write anyway. It is NOT a second code path - see startManual().
    ///
    /// SHIFT EVIDENCE (docs/shift-evidence.md). A tap that would FINISH this worker's open shift (a
    /// tap-out or a building switch) first asks prepareCompletion, which holds it back ONLY for a
    /// shift known to require photo proof; every other tap, a start always, falls straight through
    /// and `proofApproved` is true on the re-entry after the proof. The open row is THIS worker's
    /// (openRow), so another account's forgotten shift can neither start the proof flow nor
    /// swallow B's tap, and `switched` is the SAME building rule the branch below applies.
    private func handleTap(_ locationId: String, manual: Bool = false,
                           clientUuid: UUID? = nil, startTime: Date? = nil,
                           proofApproved: Bool = false) {
        if let running = openRow, !proofApproved {
            prepareCompletion(switched: leavesBuilding(of: running, for: locationId)) {
                handleTap(locationId, manual: manual, clientUuid: clientUuid, startTime: startTime,
                          proofApproved: true)
            }
            return
        }
        let trace = Telemetry.beginTap(locationId: locationId, cachedLocations: sites.count)
        let write = trace.child("db", "shift.local_write")

        // decision-10 wants unresolved shifts resolved before the app is USED. Capturing a
        // timestamp is not use, it is capture: the old code refused the tap outright, so a
        // worker at the door at 06:02 got an alert, resolved an unrelated three-day-old
        // auto-closed shift, and tapped again at 06:05 - three minutes of paid time gone,
        // and only if they tapped again at all. The invariant decision-10 protects is that
        // no shift reaches payroll with an unconfirmed end time, and a NEW open shift does
        // not touch it. So: record first, then force the resolver sheet (not a dismissible
        // alert) so the pressure stays and the data loss goes.
        let mustResolve = !unresolved.isEmpty

        let action: String
        let touched: Shift
        // THIS worker's open row and nobody else's. On a shared phone worker A's forgotten open
        // shift is still in the store; B's tap must start B's own shift, never close A's (the
        // close would go out under B's cookie and the server answers 404 unknown_shift) and
        // never auto-close it as a walk-away. A's row is left exactly as it was.
        if let running = openRow {
            running.endTime = .now
            running.closeSyncedAt = nil
            // BUILDINGS, not raw ids (decision-43): two zones of one building are one place.
            // Without this a tap-out at the building's second door auto-closes the shift as
            // "left without tapping out" and opens a new one, flagged for correction.
            if leavesBuilding(of: running, for: locationId) {
                // The worker left the last building without tapping out and is now at a
                // new one. Auto-closing is the only non-deadlocking option: the server
                // allows one open shift per worker, and they cannot walk back to the old
                // tag. Say so out loud rather than doing it behind their back.
                //
                // Flagged, not silent: the end time we just wrote is the moment they
                // arrived at the NEXT building, so the walk between sites lands on this
                // one's labour cost and no human ever confirmed the real finish time.
                // Marking it sends it through the same resolution screen as an 8h timeout
                // (decision-10), which keeps the invariant that no shift reaches payroll
                // with an unconfirmed end time. A normal tap-out stays unflagged.
                running.autoClosed = true
                switchNotice = String(localized: "Finished your open shift at \(siteName(running.locationId)) and started at \(siteName(locationId)). Confirm when you actually left \(siteName(running.locationId)) — it will not count until you do.")
                touched = startShift(at: locationId, clientUuid: clientUuid, startTime: startTime)
                action = "switch"
            } else {
                touched = running
                action = "close"
            }
        } else {
            touched = startShift(at: locationId, clientUuid: clientUuid, startTime: startTime)
            // decision-56, set ONLY on a row this call is creating. A manual clock-in is
            // unreachable while a shift is running (the button lives on the idle screen), so
            // the close and switch branches above can never be handed manual = true - and if
            // that ever changes, it must not silently re-flag somebody else's open row.
            touched.manualStart = manual
            action = manual ? "manual_open" : "open"
        }
        try? context.save()

        // AFTER the save and never before it. Everything below this line is a signal, and
        // a signal may never delay, throw into, or fail a clock-in (audit R2): arm(for:)
        // is synchronous, non-throwing, and hands every OS call to a detached Task. A
        // denied permission, Live Activities switched off and a dead network are all
        // "arm nothing" - never "reject the tap". checks/shift-signal-check.swift pins
        // this ordering by reading this function as text.
        signals.arm(for: currentRunning())

        // A zone created after the last roster fetch is unknown to this phone until the next
        // one. Its OWN task, started after the save and after the arm, so a slow or dead
        // network can neither delay the clock-in nor the push below. The reminder ladder is
        // fixed text, so it is armed once more when the real building name has arrived.
        Task {
            await refreshRoster(context: context)
            armIfStillCurrent()
        }

        write.data("ts.shift.action", action)
        write.data("ts.shift.client_uuid", touched.clientUuidString)
        write.finish()

        // `ts.roster.cached_locations` is the one field that would have diagnosed the
        // deleted guard above in five seconds instead of by reading source. That is why
        // it exists.
        Telemetry.log("nfc tap accepted", .info, [
            "ts.location.id": locationId,
            "ts.shift.action": action,
            "ts.shift.client_uuid": touched.clientUuidString,
            "ts.cold_launch": Telemetry.isColdLaunch(),
            "ts.roster.cached_locations": sites.count,
            "ts.tap.unresolved_pending": mustResolve,
        ])

        // The switch notice is a card now, not an alert, so it cannot collide with this
        // sheet and the old `alertMsg == nil` guard is gone with it: an unresolved shift
        // ALWAYS opens the resolver, including on the tap that just created one.
        if mustResolve { showResolver = true }

        Task {
            // Wraps the await rather than being started after it: a span that covers the
            // push is what shows whether the POST happened at all, and the auto-instrumented
            // http.client span lands inside this transaction because it is scope-bound.
            let push = trace.child("function", "shift.push")
            await syncPending(context: context, workerId: worker.id)
            // SIGNALS, AGAIN, now that the server has (or has not) answered. iOS freezes a
            // notification's text when it is scheduled, and the arm above ran while this start
            // was unacknowledged - so the ladder says "Not confirmed yet" until this re-arm
            // says otherwise. It follows the push inside this un-awaited Task: it cannot delay
            // the tap (already saved and armed) or the push (already done), and it is the
            // session-guarded one, so a sign-out during the request is not undone.
            armIfStillCurrent()
            if let serverId = touched.serverId { push.data("ts.shift.server_id", serverId) }
            push.data("ts.shift.outcome", outcome(of: touched))
            push.finish()
            trace.data("ts.shift.outcome", outcome(of: touched))
            trace.finish(ok: !touched.syncBlocked)
        }
    }

    /// THE ONE "did this tap leave the building the shift runs in" rule (decision-43): BUILDINGS, not
    /// raw place ids, because two zones of one building are one place. Asked by the branch in handleTap
    /// that decides close-versus-switch AND by the proof gate at the top of it, so a tap-out at a
    /// building's second door is a plain close for both - never a walk-away flagged auto_closed.
    private func leavesBuilding(of running: Shift, for locationId: String) -> Bool {
        Zones.buildingIdOf(running.locationId, zones: rosterZones.zones)
            != Zones.buildingIdOf(locationId, zones: rosterZones.zones)
    }

    private func outcome(of shift: Shift) -> String {
        if shift.syncBlocked { return "blocked" }
        return shift.isFullySynced ? "synced" : "queued"
    }

    @discardableResult
    private func startShift(at locationId: String, clientUuid: UUID? = nil, startTime: Date? = nil) -> Shift {
        let shift = Shift(workerId: worker.id, workerName: worker.name, locationId: locationId,
                          startTime: startTime ?? .now)
        // A manual start asked the server FIRST under this exact client_uuid (decision-81), so
        // the row must carry it: the sync pass then gets 200 duplicate, never a second open.
        if let clientUuid { shift.clientUuid = clientUuid }
        context.insert(shift)
        return shift
    }
}

// MARK: - Rows

/// One shift as a card with the TIME RANGE as its dominant line (Android ShiftRow, an 18 dp WorkerCard:
/// name and state, date, large "HH:mm – HH:mm", duration, delivery line). A List row on the idle
/// screen and in History, so it carries its own chrome-free row (`workerListRow`): the card is the
/// only surface, and History's swipe-to-delete still has a row to swipe.
struct ShiftRow: View {
    let shift: Shift
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: name)
                    .font(WorkerStyle.Typeface.rowName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // decision-56 §5: "every list that shows shifts must show this". A manual row
                // is never indistinguishable from a tap-confirmed one, on the worker's own
                // phone either - the admin should not be the only one who can tell.
                if shift.manualStart || shift.manualClose { pill("Manual", .blue) }
                if shift.isOpen { pill("In progress", .orange) }
                else if shift.autoClosed && shift.correctedAt == nil { pill("Auto-closed", .red) }
                else if shift.correctedAt != nil { pill("Corrected", .purple) }
            }
            Text(shift.startTime.formatted(date: .abbreviated, time: .omitted))
                .font(WorkerStyle.Typeface.caption)
                .foregroundStyle(.secondary)
            if let end = shift.endTime {
                // THE DOMINANT LINE: the range, in the app's heaviest row style, in tabular digits.
                Text("\(shift.startTime.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(WorkerStyle.Typeface.lead)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                if let d = shift.duration {
                    Text(verbatim: fmtDur(d))
                        .font(.subheadline)
                }
            } else {
                Text(shift.startTime.formatted(date: .omitted, time: .shortened))
                    .font(WorkerStyle.Typeface.lead)
                    .monospacedDigit()
            }
            syncStatus
        }
        .workerCard()
        .workerListRow()
    }

    /// A failed sync is never invisible. `syncBlocked` means nobody is retrying and the
    /// worker has to involve the admin, so it says that in red rather than "pending".
    ///
    /// An unsent row never says "Sending..." (Android sync_waiting): a row taken in a basement is not
    /// being sent, it is WAITING for a connection, and the last attempt rides under it so the worker can
    /// tell "the phone is trying and failing" from "the phone has not had a signal since".
    @ViewBuilder private var syncStatus: some View {
        if let err = shift.syncError {
            Label(err, systemImage: shift.syncBlocked ? "xmark.octagon.fill" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption)
                .foregroundStyle(shift.syncBlocked ? .red : .orange)
        } else if shift.isFullySynced {
            Label("Sent", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Waiting for a connection", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                if let attempt = shift.lastAttemptAt {
                    Text("Last tried \(attempt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not attempted yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// TASK-298: the parameter is a LocalizedStringKey, not a String, ON PURPOSE.
/// Text(_ content: S) where S: StringProtocol is the VERBATIM initializer - it looks
/// nothing up, so every pill shipped its English literal on a German device. Only
/// Text(_ key: LocalizedStringKey) consults the catalogue. All call sites pass literals,
/// so they compile unchanged; a future caller with a RUNTIME String will not compile,
/// which is the point - it would have to say what key it means.
///
/// Not private any more (decision-83, P7): the finished-shift receipt and My hours draw the SAME
/// pills, so there is one place the Blue Hour reskin has to restyle them.
func pill(_ t: LocalizedStringKey, _ c: Color) -> some View {
    Text(t).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
        .background(c.opacity(0.2)).foregroundStyle(c).clipShape(Capsule())
}

/// Not private: LegacyClassifier's "worthless" ceiling is defined as "what this renders
/// as 0h 0m", and MigrationReceiptView shows archived rows with the same spelling.
func fmtDur(_ s: TimeInterval) -> String { "\(Int(s) / 3600)h \((Int(s) % 3600) / 60)m" }

// MARK: - Resolution (decision-10)

/// The 8h timer closed these at start+8h, which is a guess. A human has to say what the
/// real finish time was before that guess becomes payroll truth.
struct ResolveSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Binding var shifts: [WireShift]
    let siteName: (String) -> String

    @State private var picked: [Int: Date] = [:]
    @State private var proofTarget: WireShift?
    @State private var error: String?
    @State private var busy = false
    /// How many there were when this sheet opened, so the worker can watch the queue
    /// shrink. decision-10 point 3 asked for this and neither platform had it.
    @State private var total = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if total > 1 {
                        Text("\(total - shifts.count + 1) of \(total) confirmed")
                            .font(.footnote.weight(.semibold))
                    }
                    Text("These shifts were closed automatically after 8 hours. Enter when you actually finished.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(shifts) { shift in
                    Section(shift.locationName ?? siteName(shift.locationId)) {
                        LabeledContent("Started",
                                       value: shift.startTime.formatted(date: .abbreviated, time: .shortened))
                        DatePicker("Finished",
                                   selection: binding(for: shift),
                                   in: Self.range(for: shift))
                        Button("Save finish time") { Task { await save(shift) } }
                            .disabled(busy)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Unfinished shifts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
            .task { if total == 0 { total = shifts.count } }
            .sheet(item: $proofTarget) { shift in
                if let key = shift.clientUuid {
                    ShiftProofSheet(clientUuid: key) { proofId in
                        Task { await save(shift, proofId: proofId) }
                    }
                }
            }
        }
    }

    /// A DatePicker traps on an empty range, so the bounds are clamped rather than
    /// trusted: a phone with a skewed clock could otherwise report a start in the future.
    private static func range(for shift: WireShift) -> ClosedRange<Date> {
        let now = Date.now
        return min(shift.startTime, now.addingTimeInterval(-60))...now
    }

    private func binding(for shift: WireShift) -> Binding<Date> {
        Binding(get: { picked[shift.id] ?? shift.endTime ?? .now },
                set: { picked[shift.id] = $0 })
    }

    private func save(_ shift: WireShift, proofId: String? = nil) async {
        if shift.proofOfWorkRequired == true && proofId == nil {
            guard shift.clientUuid != nil else {
                error = String(localized: "This shift is missing its location and can't be sent.")
                return
            }
            proofTarget = shift
            return
        }
        busy = true
        defer { busy = false }
        let end = picked[shift.id] ?? shift.endTime ?? .now
        if let failure = await resolveShift(context: context, shift: shift, end: end, proofId: proofId) {
            error = failure
            return
        }
        error = nil
        shifts.removeAll { $0.id == shift.id }
        if shifts.isEmpty { dismiss() }
    }
}

// MARK: - History tab

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    /// The signed-in worker. History lists, totals and DELETES only this worker's rows: on a
    /// shared phone the store also holds everybody else's unsent hours, and a swipe must never
    /// be able to reach them (WorkerScope.swift; nothing is ever deleted on sign-out).
    let worker: WireWorker
    /// DEVICE-WIDE (every account's rows) - read only through WorkerScope, see LogView.
    @Query(sort: \Shift.startTime, order: .reverse) private var allShifts: [Shift]
    @Query private var sites: [Site]
    @Environment(RosterZones.self) private var rosterZones
    private func siteName(_ id: String) -> String {
        rosterZones.buildingName(of: id, sites: sites) ?? String(localized: "Unknown location")
    }

    /// This worker's rows, newest first. The list, the totals and the swipe-delete all use it.
    private var mine: [Shift] { allShifts.forWorker(worker.id) }
    private var completed: [Shift] { allShifts.completed(for: worker.id) }
    private var totalHours: Double { completed.compactMap(\.duration).reduce(0, +) / 3600 }
    private var weekHours: Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return completed.filter { $0.startTime >= start }.compactMap(\.duration).reduce(0, +) / 3600
    }

    /// PUSHED, NEVER A TAB: SettingsView puts this on its own NavigationStack (Android: More's
    /// identity card opens the unchanged HistoryScreen under a Back button), so this view has no
    /// stack of its own any more - a second one inside the first would draw two navigation bars.
    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("This week", value: String(format: "%.1f h", weekHours))
                LabeledContent("Total", value: String(format: "%.1f h", totalHours))
            }
            Section("Shifts") {
                if mine.isEmpty { Text("No shifts yet.").foregroundStyle(.secondary) }
                ForEach(mine) { ShiftRow(shift: $0, name: siteName($0.locationId)) }
                    // Deleting only drops the local copy; anything already sent stays
                    // on the server, which is what payroll is paid from. The indices
                    // are into THIS WORKER's rows (`mine` is already scoped), so a swipe
                    // cannot reach another account's unsent hours.
                    .onDelete { idx in
                        let rows = mine
                        idx.map { rows[$0] }.forEach(context.delete)
                        try? context.save()
                    }
            }
        }
        .workerListPage()
        .navigationTitle("History")
    }
}

// MARK: - Settings tab

/// No picker any more (decision-22). "Who are you" is not a setting a worker gets to
/// choose - it is the server's answer to their Apple ID, shown here read-only.
struct SettingsView: View {
    @Environment(Session.self) private var session
    let worker: WireWorker
    /// DEVICE-WIDE (every account's rows), read only through WorkerScope - see LogView. Used for ONE
    /// question: does THIS worker have an open shift? (History is offered only while they have not.)
    @Query private var allShifts: [Shift]
    /// What this stack has pushed that a shift starting must take back. Only History is value-based.
    @State private var path: [SettingsRoute] = []

    private enum SettingsRoute: Hashable { case history }

    private var shiftOpen: Bool { allShifts.openShift(for: worker.id) != nil }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Signed in as") {
                    LabeledContent("Name", value: worker.name)
                        .accessibilityLabel("Signed in as \(worker.name)")
                    // decision-83: the server's last 60 days, read-only (Android: More > "Meine Stunden",
                    // in the identity card). A pushed screen that asks the server on every entry and
                    // keeps nothing; it takes the worker so its request is made as THEM and dropped if
                    // somebody else holds the session by the time it lands.
                    NavigationLink("My hours") { MyHoursView(worker: worker) }
                    // The phone's own log of what it wrote, only while no shift is open (Android:
                    // `if (log.open == null)` in the same card). It was a tab; nothing in it is
                    // time-critical, so it is not offered mid-shift and is popped if a shift starts.
                    if !shiftOpen {
                        NavigationLink("History", value: SettingsRoute.history)
                    }
                }
                Section {
                    Text("Hours, locations and payroll are managed by your admin on the web.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                // decision-45: a SEPARATE identity for a SEPARATE credential. Reachable
                // from here because a worker's own phone may also be the one an operator
                // uses to mount or test a tag — it is additive, and touches nothing above.
                //
                // Through the SAME gate as the sign-in screen's link, never straight into
                // WriteTagScreen: those screens no longer carry a code field of their own
                // (decision-54 §4), so a direct link from here would be the one unguarded
                // way in left.
                Section {
                    NavigationLink("Write or test tags") { OperatorHomeScreen() }
                } footer: {
                    Text("For staff who mount and test NFC tags. This never opens a shift.")
                        .font(.footnote)
                }
                Section {
                    // Destructive, so BORDERED and never filled or borderless (2026-08-29
                    // UX audit): a plain text row reads like a label until it is pressed.
                    Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                        .buttonStyle(.bordered)
                        .disabled(session.busy)
                } footer: {
                    Text("Shifts already sent stay on the server. Anything still waiting to send will be blocked until you sign back in.")
                        .font(.footnote)
                }
                // decision-52: same wording Android's Settings → UpdateSection already
                // renders. Reads the native fields Xcode already writes into the built
                // Info.plist from project.pbxproj's MARKETING_VERSION/
                // CURRENT_PROJECT_VERSION — no build-setting edit needed or made.
                Section {
                    Text("Installed: \(appVersion) (\(appBuild))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .history: HistoryView(worker: worker)
                }
            }
            // A shift that starts while History is open takes it away (Android dismisses it too): the
            // row is gone from the form above, and a pushed copy must not outlive it.
            .onChange(of: shiftOpen) { _, open in
                if open { path.removeAll() }
            }
        }
    }
}
