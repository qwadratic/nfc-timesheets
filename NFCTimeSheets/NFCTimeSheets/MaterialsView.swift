//
//  MaterialsView.swift
//  NFCTimeSheets
//
//  "I need something." The worker writes it in their own words, sees where it got to,
//  and is told when it is in the warehouse.
//
//  THIS SCREEN IS NOT THE PRODUCT. Clocking in is. Nothing here is on the tap path,
//  nothing here is awaited by LogView, and every failure below ends as a sentence on a
//  row rather than as a blocked screen.
//
//  THE BLUE HOUR RESKIN (TASK-365.12 / iOS B4), ported from android/.../ui/TimeSheetApp.kt
//  `MaterialScreen` (1831-2012) at 60f6886. A page heading; the arrivals as cards; then the
//  composer as ONE FLAT BLOCK on the page - the heading with its small mark, the field with its
//  visible example, one full-width inverse-filled button, a visible "saved" line and ONE short
//  no-push sentence with the long explanation behind a button (decision-23: there is no push,
//  and nothing on this screen may promise a notification). Submit and queue logic are untouched.
//
//  EVERY SENTENCE HERE IS A CATALOGUE KEY, in German and English (decision-8, AGENTS.md i18n).
//  The status line used to be built as a runtime `String` and handed to `Label`, whose String
//  initialiser is VERBATIM - so a German phone read "Waiting for the office". It is a
//  `LocalizedStringKey` now, and checks/worker-reskin-check.swift pins that it stays one.
//

import SwiftData
import SwiftUI

struct MaterialsView: View {
    @Environment(MaterialStore.self) private var store
    let worker: WireWorker

    /// Read-only, from the app's existing container. Used for two cosmetic things: which
    /// building to attach as CONTEXT, and what to call it. Nothing branches on either -
    /// a request with no building is a perfectly good request.
    ///
    /// DEVICE-WIDE (every account's rows), read only through WorkerScope: the building a
    /// request carries is the SIGNED-IN worker's open shift, never a colleague's leftover one
    /// ("For <A's building>" must not appear on B's request).
    @Query(sort: \Shift.startTime, order: .reverse) private var allShifts: [Shift]
    @Query private var sites: [Site]
    @Environment(RosterZones.self) private var rosterZones

    @State private var typed = ""
    /// The request just accepted into the queue: "Request saved ..." stays visible until the worker
    /// starts typing the next one (Android `justSaved`, reset by the field's own change).
    @State private var justSaved = false
    /// The "How updates work" dialog.
    @State private var showUpdatesInfo = false
    @FocusState private var writing: Bool

    private var openShift: Shift? { allShifts.openShift(for: worker.id) }
    /// The BUILDING of the open shift, never the zone that was tapped: POST /material-requests
    /// validates its location against buildings only, so a zone id answers 422 and the row
    /// stays blocked on the phone for ever. nil (building not cached yet) is a perfectly good
    /// request, just one without a building (decision-43; see Zones.materialContext).
    private var contextLocationId: String? {
        openShift.flatMap { rosterZones.materialContext(of: $0.locationId, sites: sites) }
    }
    private func siteName(_ id: String) -> String? { sites.first { $0.locationId == id }?.name }

    private var canSubmit: Bool { MaterialQueue.normalise(typed) != nil }

    var body: some View {
        NavigationStack {
            // A List still (pull-to-refresh is the refresh control, as on the idle screen), every row
            // chrome-free: the page heading, the arrivals and the requests are cards or bare content on
            // the page, and the composer is one flat block - never a stock grouped Section.
            List {
                Text("Materials")
                    .font(WorkerStyle.Typeface.title)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .workerListRow()
                arrivals
                compose
                history
            }
            .workerListPage()
            // Monochrome chrome like the idle list: the text buttons are the ink, not the system accent.
            .tint(Color.primary)
            .scrollDismissesKeyboard(.interactively)
            // The page heading above is the title (Android MaterialScreen's headlineSmall), so the bar
            // stays, empty and inline - the same arrangement as the idle and running screens.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.sync(workerId: worker.id) }
            // ContentView.start() already ran at launch and read the file; this is the
            // poll on opening the tab. It is a no-op until the file has been read - see
            // MaterialStore.started, which exists so this cannot flush an empty cache
            // over a queued request.
            .task(id: worker.id) { await store.sync(workerId: worker.id) }
            // THE LONG EXPLANATION, behind the short line's button (Android AlertDialog). An alert and
            // not a sheet: it is words and one dismissal, and this screen presents nothing else.
            .alert("How updates work", isPresented: $showUpdatesInfo) {
                Button("Dismiss", role: .cancel) {}
            } message: {
                if contextLocationId == nil {
                    Text("The office reads these on the web. Open this tab to see when something arrives - your phone will not notify you.")
                } else {
                    Text("Sent with the building you're clocked into now, so the office knows where you are. Open this tab to see when something arrives - your phone will not notify you.")
                }
            }
        }
    }

    // MARK: - Arrived, and nobody has been told

    /// The whole reason this screen polls. `arrived` + no `seen_at`.
    @ViewBuilder private var arrivals: some View {
        if !store.unseenArrivals.isEmpty {
            Section("Ready to collect") {
                ForEach(store.unseenArrivals) { request in
                    VStack(alignment: .leading, spacing: 8) {
                        Label("At the warehouse", systemImage: "tray.and.arrow.down.fill")
                            .font(WorkerStyle.Typeface.rowName)
                            .foregroundStyle(.green)
                        Text(request.itemName ?? request.body)
                            .font(.body)
                        if let arrived = request.arrivedAt {
                            Text("Arrived \(arrived.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Got it") {
                            Task { await store.markSeen(request) }
                        }
                        .buttonStyle(.workerPrimary)
                        .accessibilityHint("Removes this from the ready-to-collect list")
                    }
                    .workerCard()
                    // One item to VoiceOver, with the state said out loud rather than
                    // only shown in green. The button stays separately focusable.
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Ready to collect: \(request.itemName ?? request.body)")
                    .workerListRow()
                }
            }
            .headerProminence(.increased)
        }
    }

    // MARK: - Ask

    /// THE FLAT COMPOSER (Android: a Column on the page, no card): the heading with the small supplies
    /// mark, the outlined field with its visible example, the building it will carry, one full-width
    /// inverse-filled button, the visible "saved" line and the short no-push sentence.
    ///
    /// decision-23: the server's dependencies are pg + @sentry/node. There is no APNs certificate and
    /// no device-token table, so there is NO PUSH. This app POLLS. Promising a notification to somebody
    /// who then does not get one is the difference between a late delivery and a broken product - so
    /// the short line always says so, and the long explanation lives behind its button.
    @ViewBuilder private var compose: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Ask for something")
                    .font(WorkerStyle.Typeface.lead)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WorkerGlyph(systemName: "shippingbox", size: 64, scales: false)
            }

            // THE FIELD: outlined, two to eight lines (Android OutlinedTextField minLines 2 / maxLines 8,
            // 16 dp corners). The whole box focuses it, not only the line of text.
            TextField("What do you need?", text: $typed, axis: .vertical)
                .lineLimit(2...8)
                .focused($writing)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: WorkerStyle.buttonRadius, style: .continuous)
                        .fill(WorkerStyle.card)
                        .onTapGesture { writing = true }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WorkerStyle.buttonRadius, style: .continuous)
                        .stroke(writing ? Color.primary : Color(uiColor: .opaqueSeparator), lineWidth: writing ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("What do you need?")
                .onChange(of: typed) { _, new in
                    // The worker has started the next request: the previous one's "saved" line goes.
                    // (An emptied field is the submit itself and must not clear the line it just set.)
                    if !new.isEmpty { justSaved = false }
                    // Hard stop at the server's own limit rather than a 400 the worker
                    // cannot read. Truncating only when it is exceeded means the cursor
                    // is never moved under someone who is still typing.
                    if new.count > MaterialAPI.bodyMaxLength {
                        typed = String(new.prefix(MaterialAPI.bodyMaxLength))
                    }
                }

            // THE VISIBLE EXAMPLE (Android supportingText worker_material_example). It replaces the long
            // sentence that used to be a VoiceOver hint nobody sighted ever read.
            Text("For example: 2 mops, glass cleaner")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if typed.count > MaterialAPI.bodyMaxLength - 200 {
                Text("\(typed.count) of \(MaterialAPI.bodyMaxLength) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let id = contextLocationId {
                // The building is CONTEXT only; costs are still split by labour hours (decision-6).
                // Each branch is its own literal so it is a LocalizedStringKey: a String built with
                // `?:` and handed to Label/Text is the verbatim initialiser and ships English.
                Group {
                    if let name = siteName(id) {
                        Text("For \(name)")
                    } else {
                        Text("For the building you're in now")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Button("Send request") {
                // Only clear the field if the row was actually accepted. Clearing first
                // and asking later is how a worker's typing disappears into nothing.
                guard store.submit(body: typed, locationId: contextLocationId, workerId: worker.id) else { return }
                typed = ""
                writing = false
                justSaved = true
                AccessibilityNotification.Announcement(
                    String(localized: "Request saved. It will be sent as soon as you're online.")).post()
            }
            .buttonStyle(.workerPrimary)
            .disabled(!canSubmit)

            // Visible, not only announced (Android: a polite live region under the button).
            if justSaved {
                Text("Request saved. It will be sent as soon as you're online.")
                    .font(.subheadline)
            }

            // ONE short line, always there; the explanation is one button away.
            Text("Check updates here. No push notifications.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("How updates work") { showUpdatesInfo = true }
                .buttonStyle(.workerQuietLeading)
        }
        .workerListRow()
    }

    // MARK: - Everything, newest first

    @ViewBuilder private var history: some View {
        Section("Your requests") {
            if store.featureUnavailable {
                Label("The office hasn't switched this on yet. Anything you write is saved and sent as soon as they do.",
                      systemImage: "clock.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .workerListRow()
            }
            if store.cacheWasCorrupt {
                Label("Some older requests on this phone couldn't be read. Anything already sent is safe on the server.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .workerListRow()
            }
            if store.entries.isEmpty {
                Text("Nothing asked for yet.")
                    .foregroundStyle(.secondary)
                    .workerListRow()
            }
            ForEach(store.entries) { entry in
                switch entry {
                case .queued(let row): QueuedMaterialRow(row: row, siteName: siteName)
                case .sent(let row): SentMaterialRow(row: row)
                }
            }
        }
        .headerProminence(.increased)
    }
}

// MARK: - Rows

/// Written, not yet acknowledged by the server. Never silently pretty: an unsent request
/// says it is unsent, and a rejected one says a human has to act.
private struct QueuedMaterialRow: View {
    let row: QueuedMaterialRequest
    let siteName: (String) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.body).font(.body)
            if let id = row.locationId, let name = siteName(id) {
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            if let error = row.errorMessage {
                Label(error, systemImage: row.blocked ? "xmark.octagon.fill" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(row.blocked ? .red : .orange)
            } else {
                Label("Sending…", systemImage: "arrow.up.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .workerCard()
        .accessibilityElement(children: .combine)
        .workerListRow()
    }
}

/// The server's copy. `status` is the only thing that says where it got to, and it is
/// always rendered as WORDS - the colour is a second signal, never the only one.
private struct SentMaterialRow: View {
    let row: WireMaterialRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.body).font(.body)
            if let item = row.itemName {
                Text(row.quantity.map { "\($0) × \(item)" } ?? item)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let location = row.locationName {
                Text(location).font(.caption).foregroundStyle(.secondary)
            }
            Label(Self.statusText(row), systemImage: Self.statusIcon(row))
                .font(.subheadline)
                .foregroundStyle(Self.statusColour(row))
            if let note = row.adminNote, !note.isEmpty {
                // The office's own words about this decision. It is the only explanation
                // a refused worker gets, so it is shown rather than swallowed.
                Text("Note from the office: \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
        .workerCard()
        .accessibilityElement(children: .combine)
        .workerListRow()
    }

    /// A LocalizedStringKey and NOT a String, on purpose: `Label(_: S: StringProtocol, ...)` is the
    /// verbatim initialiser, so the sentences below used to reach a German phone in English (the
    /// "statusText returns unlocalized literals" note of the Android-parity sweep). Each case is a
    /// catalogue key in both languages.
    ///
    /// An unknown status is reported as unknown. Inventing "in progress" for a value this
    /// build has never seen would be a guess shown as a fact.
    static func statusText(_ row: WireMaterialRequest) -> LocalizedStringKey {
        switch row.status {
        case .submitted: return "Waiting for the office"
        case .approved: return "Approved - not ordered yet"
        case .ordered: return "Ordered"
        case .arrived: return row.seenAt == nil ? "At the warehouse" : "Collected"
        case .rejected: return "Not approved"
        case nil: return "Status unknown - ask your admin"
        }
    }

    static func statusIcon(_ row: WireMaterialRequest) -> String {
        switch row.status {
        case .submitted: return "paperplane"
        case .approved: return "checkmark.circle"
        case .ordered: return "shippingbox"
        case .arrived: return "tray.and.arrow.down.fill"
        case .rejected: return "xmark.circle"
        case nil: return "questionmark.circle"
        }
    }

    static func statusColour(_ row: WireMaterialRequest) -> Color {
        switch row.status {
        case .arrived: return row.seenAt == nil ? .green : .secondary
        case .rejected: return .red
        case .submitted, .approved, .ordered, nil: return .secondary
        }
    }
}
