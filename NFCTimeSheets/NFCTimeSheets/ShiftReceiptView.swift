//
//  ShiftReceiptView.swift
//  NFCTimeSheets
//
//  THE "SHIFT FINISHED" RECEIPT, drawn (decision-83, TASK-365.8 / iOS P7). Ported from Android's
//  TimeSheetApp.kt `CompletedShiftReceipt` at 60f6886: the heading, the building, "HH:mm - HH:mm",
//  the duration, the correction state, ONE delivery line, and a full-width Continue. WHEN it is
//  offered, what the delivery line says and when the check may play are ShiftReceipt.swift and
//  ConfirmationMotion.swift (Foundation-only, check-covered); this file only draws their answers.
//
//  IT IS INLINE, NEVER A DIALOG. LogView puts it in a List Section at the top of the idle screen -
//  after the unresolved banner, before the delivery rows - so a tag tap, the tab bar, the resolver
//  banner and the resolver sheet all keep working while it is up. The two start Sections are not
//  drawn meanwhile and the row is filtered out of Recent (Android replaces its start card with it).
//
//  WHAT IT TAKES: the `Shift` itself, not a copy. The delivery line and the motion's `confirmed`
//  are read from the row's own fields in `body`, so when SwiftData publishes the ACK (closeSyncedAt
//  set, syncError cleared) THIS view re-renders from the same object every other screen reads, and
//  the flip is seen at the moment it happens - never from a value captured a render earlier.
//
//  THE MOTION wraps only the text block, not Continue: ring, check, then the receipt settles
//  (ConfirmationMark.swift). It plays only when `ShiftReceipt.isConfirmed` says the server has
//  everything and nothing is left to resolve; a queued, failed or refused finish shows its delivery
//  line and never a check.
//
//  NO SURFACE OF ITS OWN: no background, card or corner radius, no fixed colour but the semantic
//  state colours the existing ShiftRow lines already use. Pills are the shared `pill`; the
//  duration is `fmtDur` unchanged. The Blue Hour reskin (B1-B5) restyles the container.
//
//  STRINGS: English sentence = key, German in Localizable.xcstrings (Android's, verbatim). A state
//  that changes the words is a `switch` of literals, never a ternary of two (TASK-298).
//

import SwiftUI

extension Shift {
    /// The receipt's identity for this row: nil while it has no finish time.
    var receiptIdentity: ShiftReceipt.Identity? {
        endTime.map { ShiftReceipt.Identity(clientUuid: clientUuidString, endedAt: $0) }
    }
}

struct ShiftReceiptView: View {
    let shift: Shift
    /// The building's name, already resolved by the caller (the zone's building, or "Unknown location").
    let name: String
    let onContinue: () -> Void

    var body: some View {
        if let end = shift.endTime {
            let row = shift.deliveryRow()
            let needsResolution = shift.autoClosed && shift.correctedAt == nil
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Shift finished")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("\(shift.startTime.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let duration = shift.duration {
                        Text(verbatim: fmtDur(duration))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    badges
                    DeliveryLine(delivery: ShiftReceipt.delivery(row: row, syncError: shift.syncError, now: .now))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .confirmationMotion(
                    kind: .clockOut,
                    identity: ConfirmationMotion.identity(clockOutOf: shift.clientUuidString, endedAt: end),
                    confirmed: ShiftReceipt.isConfirmed(row: row, syncError: shift.syncError, needsResolution: needsResolution),
                    eventTime: end,
                    ink: .primary)

                // Explicitly styled: inside a List row a default-style Button swallows the whole row.
                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.workerPrimary)
            }
            .padding(.vertical, 8)
        }
    }

    /// Manual, then Corrected or Auto-closed: ShiftRow's order and colours, through the shared pill.
    @ViewBuilder private var badges: some View {
        let all = ShiftReceipt.badges(manualStart: shift.manualStart, manualClose: shift.manualClose,
                                      autoClosed: shift.autoClosed, correctedAt: shift.correctedAt)
        if !all.isEmpty {
            HStack(spacing: 8) {
                ForEach(all, id: \.self) { badge in
                    switch badge {
                    case .manual: pill("Manual", .blue)
                    case .corrected: pill("Corrected", .purple)
                    case .autoClosed: pill("Auto-closed", .red)
                    }
                }
            }
        }
    }
}

/// The ONE delivery line (ShiftReceipt.delivery). The words and the glyphs are ShiftRow's, so the
/// receipt and the Recent rows under it never say two things about one shift.
private struct DeliveryLine: View {
    let delivery: ShiftReceipt.Delivery

    var body: some View {
        switch delivery {
        case .problem(let sentence, let blocked):
            Label {
                Text(verbatim: sentence)
            } icon: {
                Image(systemName: blocked ? "xmark.octagon.fill" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
            }
            .font(.footnote)
            .foregroundStyle(blocked ? .red : .orange)
            .multilineTextAlignment(.center)
        case .sent:
            Label("Sent", systemImage: "checkmark.icloud")
                .font(.footnote)
                .foregroundStyle(.green)
        case .sending:
            Label("Sending…", systemImage: "arrow.up.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .savedLocally:
            Label("Saved on this phone · not yet confirmed", systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
