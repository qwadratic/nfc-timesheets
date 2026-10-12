//
//  WriteTagScreen.swift
//  NFCTimeSheets
//
//  Reachable ONLY through OperatorHomeScreen (decision-54 §4). Mints an id, presents the
//  system NFC sheet, shows exactly one Outcome, then reports it - and the report is SOFT,
//  never downgrading a verified write (decision-49). NOTHING here opens or closes a shift:
//  OperatorTagAPI carries the ts_operator cookie, which no shift route accepts (decision-45).
//
//  THE CODE FIELD THAT USED TO LIVE HERE IS GONE, and that is not a loosening: the gate
//  moved UPSTREAM of the navigation link, so this screen is unreachable without an operator
//  session instead of merely refusing to act without one. What is left is the DEFENSIVE
//  half - a session that dies while this screen is open pops back to the gate rather than
//  growing a second code-entry UI here, which is exactly the duplication decision-54 §5
//  set out to delete.
//

import SwiftUI

struct WriteTagScreen: View {
    @Environment(OperatorSession.self) private var operatorSession
    @Environment(\.dismiss) private var dismiss
    /// The app language's locale (decision-74). Every sentence this screen builds in code asks for it, so
    /// a language switch re-evaluates them, and a message that was STORED when an outcome arrived is said
    /// again in it (AppLanguage.rerender).
    @Environment(\.locale) private var locale
    @State private var pendingId = OperatorTagMint.mintId()
    // The actual bytes this build would write, computed the SAME way TagWriter.plan() does
    // (TagLink.uriFor), so what the operator sees here can never drift from what lands on
    // the card. Shown on screen because "Card id" alone is not something a person can
    // recognise as a scannable link - see the note on `pendingUri` below.
    @State private var writer = TagWriter()
    @State private var outcome: TagWriter.Outcome?
    @State private var confirmedFor: String?
    @State private var confirmText = ""
    @State private var busy = false
    @State private var report: ReportState = .idle
    // The id that actually LEFT this phone. `pendingId` is re-minted the moment a report
    // lands, so it is already the NEXT card by the time the zone step runs - resolving
    // against it would 404 on a tag nobody ever reported.
    @State private var reportedId: String?
    @State private var zone: ZoneState = .idle
    @State private var locations: [WireOperatorLocation] = []
    @State private var pickedLocationId: String?
    @State private var zoneName = ""

    private enum ReportState: Equatable {
        case idle, sending, sent
        case failed
    }

    /// The zone step, modelled the same way the report above it is: one enum, one line of
    /// text per case (see `zoneText`), no scattered booleans. `.failed` carries the server's
    /// error CODE rather than a sentence, because the sentence belongs next to the field.
    private enum ZoneState: Equatable {
        case idle, loading, picking, submitting
        /// The zone's id and whether it has a building are KEPT, not just the sentence:
        /// the button below needs the id to open that zone's test, and the hint is only true
        /// for a bound one (decision-76 §3).
        case created(zoneId: String, bound: Bool, message: String)
        case failed(String)
    }

    var body: some View {
        Form {
            writeSections
        }
        .navigationTitle("Write a tag")
        // The session went away underneath us - expired, revoked, or signed out on another
        // screen. Back to the gate, which is the ONE place a code is typed now.
        .onChange(of: operatorSession.operatorInfo == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    /// EXACTLY ONE of these renders at a time (WriteTagStep). They used to be three
    /// independent `if`s, which is how a second card in one session ended up showing the
    /// mint plan, a write result and a stale report failure all at once.
    @ViewBuilder
    private var writeSections: some View {
        Group {
            switch step {
            case .plan: planSection
            case .result: resultSection
            // ONLY after the office knows about the card. Resolving a tag the server has
            // never heard of is a guaranteed 404, so this step cannot come earlier - and a
            // failed report is not a dead end, because it keeps the screen on `.result`,
            // where the retry button lives.
            case .zone: zoneSection
            }

            #if DEBUG
            mockSection
            #endif
        }
    }

    #if DEBUG
    /// Absent from a Release build, byte for byte - see OperatorMockFlows.swift. The button
    /// does NOT draw a canned screen: it hands the state machine the outcome a successful
    /// write would have produced and then lets the SHIPPING report + zone steps run against
    /// mocked responses, so what gets walked here is this file's real code.
    @ViewBuilder
    private var mockSection: some View {
        Section("Simulate (debug builds only)") {
            Text("No NFC, no network. A simulator has neither.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(OperatorMockFlow.writeThenPickBuilding.label) {
                Task { await simulateWrite(OperatorMockFlow.writeThenPickBuilding) }
            }
            .disabled(busy)
            Button(OperatorMockFlow.writeThenSkipBuilding.label) {
                Task { await simulateWrite(OperatorMockFlow.writeThenSkipBuilding) }
            }
            .disabled(busy)
        }
    }

    /// The only thing bypassed is the radio. Everything after this line - the report, the
    /// re-mint of `pendingId`, the building fetch, the picker, `createZone()` - is untouched
    /// shipping code talking to OperatorFlowAPI's mocked half.
    private func simulateWrite(_ flow: OperatorMockFlow) async {
        OperatorMocks.arm(flow)
        resetForNewWrite()
        busy = true
        let id = OperatorTagMint.mintId()
        outcome = OperatorMocks.writtenOutcome(id: id)
        busy = false
        await sendReport(id)
        // The difference between the two scenarios, seeded rather than narrated: one arrives
        // at the picker with a building already chosen, the other with Skip standing.
        pickedLocationId = flow == .writeThenPickBuilding ? OperatorMocks.locations.first?.id : nil
        zoneName = "Stiege 2"
    }
    #endif

    @ViewBuilder
    private var planSection: some View {
        Section {
            Text("This never opens a shift. A fresh id is minted on this phone before anything is written.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // THE ACTUAL LINK, not just its id - this is what a phone reads back when it
            // taps the card, and the only thing on this screen an operator can visually
            // recognise as "a working tag" versus "some text".
            LabeledContent("Will write", value: pendingUri)
                .font(.system(.footnote, design: .monospaced))
            LabeledContent("Card id", value: pendingId)
                .font(.system(.footnote, design: .monospaced))
            if busy {
                Text(statusText)
                    .accessibilityLabel(statusText)
            }
            Button("Write") { Task { await write() } }
                .disabled(busy)
        }
    }

    /// One write attempt's ending, and everything the operator can do about it: confirm an
    /// overwrite, write again, or retry the report. One section, because they are one step.
    @ViewBuilder
    private var resultSection: some View {
        Section {
            Text(statusText)
                .accessibilityLabel(statusText)
            if let occupied = occupiedOutcome, confirmedFor != occupied.onTag {
                TextField("Last six characters", text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Overwrite") {
                    confirmedFor = occupied.onTag
                    confirmText = ""
                }
                .disabled(!WriteGuard.confirms(locationId: occupied.onTag, typed: confirmText))
            }
            if case .written(let locationId, _, _, _, _) = outcome {
                Text(reportText)
                    .font(.footnote)
                if report == .failed {
                    Button("Tell the office") { Task { await sendReport(locationId) } }
                        .disabled(busy)
                }
            }
            Button("Write") { Task { await write() } }
                .disabled(busy)
        }
    }

    @ViewBuilder
    private var zoneSection: some View {
        Section("Make this card a zone") {
            LabeledContent("Card id", value: reportedId ?? "")
                .font(.system(.footnote, design: .monospaced))
            Text(zoneText)
                .font(.footnote)
                .accessibilityLabel(zoneText)
            switch zone {
            case .idle, .loading, .submitting:
                EmptyView()
            case .created(let zoneId, let bound, _):
                // WRITING NEVER ACTIVATES A ZONE (decision-47): a zone created with a building
                // is still not a clock-in target until its card is test-scanned. Android has
                // said so, with a button straight into that test, since PR 7; without it an
                // operator walks away believing the door works and the first worker's tap is
                // refused (decision-76 §3). An unbound zone has nothing to test yet, so its
                // button leads to the building picker instead.
                if bound {
                    Text("The card is written. One test is still needed before anyone can clock in: open the test and hold the same card to the phone again.")
                        .font(.footnote)
                }
                NavigationLink(bound ? "Activate this card" : "Assign a building") {
                    VerifyZoneScreen(preselectZoneId: zoneId)
                }
            case .picking, .failed:
                TextField("Zone name", text: $zoneName)
                    .autocorrectionDisabled()
                // "Skip" is an OPTION INSIDE the picker rather than a second button:
                // skipping is an answer to the building question, not a way out of the zone
                // step, and a separate button would read as the latter. An unbound zone is a
                // legitimate resting state (decision-54 §1). Same control VerifyZoneScreen
                // binds an existing zone with - see BuildingPicker.swift.
                BuildingPicker(locations: locations, allowsSkip: true, selection: $pickedLocationId)
                Button("Create zone") { Task { await createZone() } }
                    .disabled(busy || zoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // THE WAY OUT OF THE LAST STEP, and the reason it is a button and not a note:
            // one panel renders at a time, so once a report lands this section is the WHOLE
            // screen. Without this control an operator who has just finished card 1 has no
            // reachable way to start card 2 - the Write buttons live on the other two
            // panels - and the only escape is popping the navigation stack, which nothing
            // on screen says. (A DEBUG build hid this: the Simulate section renders outside
            // the switch, so a mock walk always had a way back.)
            //
            // It resets rather than writing immediately: `resetForNewWrite()` is the SAME
            // call `write()` makes, and landing on the plan panel shows the next card's id
            // and URI before the NFC sheet opens, which is what the plan panel is for.
            Button("Write another card") { resetForNewWrite() }
                .disabled(busy)
        }
    }

    /// DERIVED, never stored - see WriteTagStep.swift.
    private var step: WriteTagStep {
        .current(hasOutcome: outcome != nil, reportSent: report == .sent,
                 hasReportedId: reportedId != nil)
    }

    private var occupiedOutcome: (onTag: String, offered: String, token: String)? {
        guard case .refusedOccupied(let onTag, let offered, let token) = outcome else { return nil }
        return (onTag, offered, token)
    }

    /// The full link for [pendingId], for display only - TagWriter recomputes the real bytes
    /// itself via NdefTag.plan(), this never feeds a write. Falls back to the bare id in the
    /// impossible case TagLink can't build one (badId), so the label is never blank.
    private var pendingUri: String {
        TagLink.uriFor(pendingId)?.absoluteString ?? pendingId
    }

    /// MINT -> WRITE -> REPORT, and the sequence itself lives in OperatorTagMint.swift now
    /// because VerifyZoneScreen's Reassign Building runs the SAME one (decision-55 §3). What
    /// stays here is this screen's own state machine around it: the spent overwrite
    /// confirmation, the re-mint, the report's retry.
    private func write() async {
        resetForNewWrite()
        busy = true
        defer { busy = false }
        let result = await OperatorTagMint.writeAndReport(
            writer: writer, id: pendingId, confirmedOverwriteOf: confirmedFor,
            onWritten: { written in
                outcome = written
                if case .written = written { report = .sending }
            })
        guard result.written else { return }
        // The confirmation is SPENT: it authorised one card, and the next card
        // presented starts from refused again.
        confirmedFor = nil
        confirmText = ""
        // A failed report is not a failed write - the retry button under `reportText` calls
        // `sendReport` again with the id that is physically on the card.
        guard result.reported else {
            report = .failed
            return
        }
        await reportLanded(result.id)
    }

    /// THE SECOND CARD OF A SESSION STARTS CLEAN. Without this, card 2's attempt inherited
    /// card 1's landed report, its reported id and its open zone step, and the view showed
    /// all of it at once. Everything here describes ONE card; nothing here is the mint.
    private func resetForNewWrite() {
        outcome = nil
        report = .idle
        reportedId = nil
        zone = .idle
        locations = []
        pickedLocationId = nil
        zoneName = ""
    }

    private func sendReport(_ locationId: String) async {
        guard !busy || report != .sending else { return }
        report = .sending
        do {
            _ = try await OperatorFlowAPI.reportTag(id: locationId)
            await reportLanded(locationId)
        } catch {
            report = .failed
        }
    }

    /// The office now knows this id, whichever call told it. One place, because the three
    /// things that must follow a landed report - remember the id, re-mint the next one, open
    /// the zone step - are the same either way.
    private func reportLanded(_ locationId: String) async {
        report = .sent
        reportedId = locationId
        // The id has now left this phone, so the NEXT card must not reuse it.
        pendingId = OperatorTagMint.mintId()
        await loadLocations()
    }

    /// The building list is a CONVENIENCE, never a gate: if it fails to load, the picker
    /// still opens with Skip as its only choice and the zone can still be created unbound,
    /// which is exactly what an operator who cannot answer the building question wanted
    /// anyway. So there is no retry button and no error state of its own here.
    private func loadLocations() async {
        zone = .loading
        locations = (try? await OperatorFlowAPI.locations()) ?? []
        pickedLocationId = nil
        zoneName = ""
        zone = .picking
    }

    private func createZone() async {
        guard let reportedId else { return }
        busy = true
        defer { busy = false }
        zone = .submitting
        do {
            let created = try await OperatorFlowAPI.resolveZone(
                tagId: reportedId,
                name: zoneName.trimmingCharacters(in: .whitespacesAndNewlines),
                locationId: pickedLocationId)
            zone = .created(zoneId: created.id, bound: created.locationId != nil,
                            message: created.locationId == nil
                            ? AppLanguage.string("Zone created: \(created.name). No building yet - bind it in Test a tag.", locale: locale)
                            : AppLanguage.string("Zone created: \(created.name).", locale: locale))
        } catch let failure as APIFailure {
            zone = .failed(failure.code)
        } catch {
            zone = .failed("network")
        }
    }

    private var zoneText: String {
        switch zone {
        case .idle: return ""
        case .loading: return AppLanguage.string("Loading buildings…", locale: locale)
        case .picking:
            return locations.isEmpty
                ? AppLanguage.string("Name this door. No buildings loaded - the zone will be created without one.", locale: locale)
                : AppLanguage.string("Name this door and pick its building, or skip the building for now.", locale: locale)
        case .submitting: return AppLanguage.string("Creating the zone…", locale: locale)
        case .created(_, _, let message): return AppLanguage.rerender(message, locale: locale)
        case .failed(let code):
            switch code {
            case "duplicate_zone_name": return AppLanguage.string("That building already has a zone with this name.", locale: locale)
            case "already_resolved": return AppLanguage.string("Somebody already made this card into a zone.", locale: locale)
            case "unknown_reported_tag": return AppLanguage.string("The office doesn't know this card yet. Tell the office first.", locale: locale)
            case "unknown_location": return AppLanguage.string("That building isn't one of ours any more.", locale: locale)
            case "network": return AppLanguage.string("No connection - try again.", locale: locale)
            default: return AppLanguage.string("Server trouble - try again.", locale: locale)
            }
        }
    }

    private var reportText: String {
        switch report {
        case .idle: return ""
        case .sending: return AppLanguage.string("Telling the office…", locale: locale)
        case .sent: return AppLanguage.string("Reported.", locale: locale)
        case .failed: return AppLanguage.string("Couldn't reach the office yet - the card is fine. Retry.", locale: locale)
        }
    }

    private var statusText: String {
        guard let outcome else {
            return busy ? AppLanguage.string("Hold your phone near the card.", locale: locale) : ""
        }
        switch outcome {
        case .written(let locationId, let uri, let bytes, let capacity, let replaced):
            let base = AppLanguage.string("Written: \(uri) — \(bytes) of \(capacity) bytes.", locale: locale)
            _ = locationId // kept in the pattern to match TagWriter.Outcome; the URL is what matters here
            switch replaced {
            case .blank:
                return base
            case .foreign(let summary):
                return base + " " + AppLanguage.string("This card held something else before: \(summary).", locale: locale)
            case .ours(let onTag):
                return base + " " + AppLanguage.string("This card held one of our own ids before: \(onTag).", locale: locale)
            }
        case .refusedTooSmall(let needed, let capacity):
            return AppLanguage.string("Too small for this tag: needs \(needed) bytes, this tag holds \(capacity).", locale: locale)
        case .refusedReadOnly:
            return AppLanguage.string("This tag is locked read-only.", locale: locale)
        case .refusedNoCapacity:
            return AppLanguage.string("This tag reports no writable space.", locale: locale)
        case .refusedNotFormatted:
            return AppLanguage.string("This tag isn't NDEF-formatted.", locale: locale)
        case .refusedBadId:
            return AppLanguage.string("Couldn't build a tag for this id.", locale: locale)
        case .refusedOccupied(let onTag, _, let token):
            if confirmedFor == onTag {
                return AppLanguage.string("Present the card again to overwrite \(onTag).", locale: locale)
            }
            return AppLanguage.string("This card already belongs to \(onTag). Type the last six characters to overwrite it: \(token).", locale: locale)
        case .unverified(let reason):
            return AppLanguage.string("The write didn't verify (\(reason)). Present this card again.", locale: locale)
        case .lost(let reason):
            return AppLanguage.string("Lost the connection (\(reason)). Try again.", locale: locale)
        case .unavailable(let message):
            return AppLanguage.rerender(message, locale: locale)
        }
    }
}
