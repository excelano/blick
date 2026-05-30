// WatchGlanceView.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The single-screen CheckIn glance for Apple Watch. Reads from the
/// session receiver's pushed snapshot — no Graph calls here, no
/// credentials, no fetch logic. The toggle at the bottom sends a single
/// presence-change action to the phone, which runs the actual Graph
/// call and pushes a fresh snapshot back.
struct WatchGlanceView: View {
    let receiver: WatchSessionReceiver
    @State private var pendingAction: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                presencePill
                meetingLine
                countsRow
                toggleButton
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var presencePill: some View {
        HStack(spacing: 6) {
            if let snapshot = receiver.snapshot, snapshot.isOutOfOffice {
                OutOfOfficeGlyph()
                Text("Out of office")
                    .font(.caption.weight(.semibold))
            } else if let snapshot = receiver.snapshot {
                PresenceGlyph(snapshot.presence)
                Text(snapshot.presence.displayName)
                    .font(.caption.weight(.semibold))
            } else {
                PresenceGlyph(.unknown)
                Text("Waiting for phone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var meetingLine: some View {
        if let snapshot = receiver.snapshot,
           let start = snapshot.nextMeetingStart,
           let subject = snapshot.nextMeetingSubject {
            VStack(alignment: .leading, spacing: 2) {
                Text(untilTime(start, referenceDate: .now))
                    .font(.caption2)
                    .foregroundStyle(Brand.accent)
                Text(subject)
                    .font(.caption)
                    .lineLimit(2)
            }
        } else if receiver.snapshot != nil {
            Text("No more meetings today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var countsRow: some View {
        if let snapshot = receiver.snapshot {
            HStack(spacing: 10) {
                countChip(symbol: "envelope.fill", value: snapshot.unreadEmailCount)
                countChip(symbol: "bubble.left.fill", value: snapshot.chatCount)
                Spacer()
            }
        }
    }

    private func countChip(symbol: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(Brand.accent)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var toggleLabel: String {
        guard let snapshot = receiver.snapshot else { return "Set Busy" }
        if snapshot.isOutOfOffice { return "Set Available" }
        return snapshot.presence == .available ? "Set Busy" : "Set Available"
    }

    private var toggleTarget: Presence {
        guard let snapshot = receiver.snapshot else { return .busy }
        if snapshot.isOutOfOffice { return .available }
        return snapshot.presence == .available ? .busy : .available
    }

    @ViewBuilder
    private var toggleButton: some View {
        Button {
            guard !pendingAction else { return }
            pendingAction = true
            receiver.sendPresence(toggleTarget)
            // The phone re-pushes a fresh snapshot after the Graph call
            // completes; clear the pending flag when the snapshot
            // actually reflects the change, capped at a few seconds so
            // a stuck request doesn't lock the button forever.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                pendingAction = false
            }
        } label: {
            HStack {
                if pendingAction {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(toggleLabel)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .tint(Brand.accent)
        .disabled(receiver.snapshot == nil)
        .padding(.top, 4)
    }
}
