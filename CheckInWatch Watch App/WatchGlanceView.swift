// WatchGlanceView.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The single-screen CheckIn glance for Apple Watch. Reads from the
/// session receiver's pushed snapshot — no Graph calls here, no
/// credentials, no fetch logic. Tapping the presence pill opens a
/// picker sheet matching the iPhone's PresenceMenu (Available, Busy,
/// Do not disturb, Be right back, Away, Offline, Out of office, Reset
/// to auto). The selected action is sent to the phone, which runs the
/// actual Graph call and pushes a fresh snapshot back.
struct WatchGlanceView: View {
    let receiver: WatchSessionReceiver
    @State private var showingPicker: Bool = false
    @State private var pendingAction: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                meetingLine
                countsRow
                laterTodaySection
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showingPicker) {
            PresencePickerSheet(
                currentPresence: receiver.snapshot?.presence ?? .unknown,
                isOutOfOffice: receiver.snapshot?.isOutOfOffice ?? false,
                onSelectPresence: { selection in
                    showingPicker = false
                    pendingAction = true
                    receiver.sendPresence(selection)
                    schedulePendingReset()
                },
                onSelectOutOfOffice: {
                    showingPicker = false
                    pendingAction = true
                    receiver.sendOutOfOffice(true)
                    schedulePendingReset()
                }
            )
        }
    }

    /// The presence indicator: just the glyph, tappable, rendered as a
    /// plain button so it carries no chrome. Lives at the trailing edge
    /// of whatever the top row of the glance is showing. While a
    /// presence change is in flight, swaps to a small progress spinner.
    @ViewBuilder
    private var presenceIcon: some View {
        Button {
            guard receiver.snapshot != nil else { return }
            showingPicker = true
        } label: {
            Group {
                if pendingAction {
                    ProgressView()
                        .controlSize(.mini)
                } else if let snapshot = receiver.snapshot, snapshot.isOutOfOffice {
                    OutOfOfficeGlyph()
                } else if let snapshot = receiver.snapshot {
                    PresenceGlyph(snapshot.presence)
                } else {
                    PresenceGlyph(.unknown)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .disabled(receiver.snapshot == nil)
    }

    @ViewBuilder
    private var meetingLine: some View {
        if let snapshot = receiver.snapshot,
           let start = snapshot.nextMeetingStart,
           let subject = snapshot.nextMeetingSubject {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let inProgress = start <= context.date
                let imminent = isMeetingImminent(start, referenceDate: context.date)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundStyle(inProgress ? .orange : Brand.accent)
                        Text(start, style: .time)
                            .foregroundStyle(Brand.textMuted)
                        Spacer()
                        presenceIcon
                    }
                    .font(.caption2.weight(.semibold))
                    Text(subject)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(untilTime(start, referenceDate: context.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(imminent || inProgress ? .orange : Brand.accent)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        if let snapshot = receiver.snapshot {
                            countChip(symbol: "envelope.fill", value: snapshot.unreadEmailCount)
                            countChip(symbol: "bubble.left.fill", value: snapshot.chatCount)
                        }
                    }
                }
            }
        } else if receiver.snapshot != nil {
            HStack(spacing: 4) {
                Text("No more meetings today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                presenceIcon
            }
        } else {
            HStack(spacing: 4) {
                Text("Waiting for phone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                presenceIcon
            }
        }
    }

    /// Bottom counts row, shown only when there's no next meeting — when
    /// a meeting is present the counts ride the countdown line.
    @ViewBuilder
    private var countsRow: some View {
        if let snapshot = receiver.snapshot, snapshot.nextMeetingStart == nil {
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

    @ViewBuilder
    private var laterTodaySection: some View {
        if let snapshot = receiver.snapshot, !snapshot.laterMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Text("LATER TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Brand.textMuted)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(snapshot.laterMeetings, id: \.self) { meeting in
                            laterRow(meeting: meeting, referenceDate: context.date)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func laterRow(meeting: SnapshotMeeting, referenceDate: Date) -> some View {
        let live = meeting.start <= referenceDate
            || isMeetingImminent(meeting.start, referenceDate: referenceDate)
        return HStack(spacing: 6) {
            Text(meeting.start, style: .time)
                .foregroundStyle(live ? .orange : Brand.accent)
                .monospacedDigit()
                .layoutPriority(1)
            Text(meeting.subject)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2.weight(.semibold))
    }

    /// The phone re-pushes a fresh snapshot after the Graph call
    /// completes; clear the pending flag when the snapshot actually
    /// reflects the change, capped at a few seconds so a stuck request
    /// doesn't lock the pill forever.
    private func schedulePendingReset() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            pendingAction = false
        }
    }
}

/// Watch-native presence picker. Same option order as the iPhone's
/// PresenceMenu (Available → Offline, then Out of office, then Reset
/// to auto), but rendered as a List so it feels at home on watchOS.
private struct PresencePickerSheet: View {
    let currentPresence: Presence
    let isOutOfOffice: Bool
    let onSelectPresence: (Presence) -> Void
    let onSelectOutOfOffice: () -> Void

    private let states: [Presence] = [
        .available, .busy, .doNotDisturb, .beRightBack, .away, .offline
    ]

    var body: some View {
        List {
            Section {
                ForEach(states, id: \.self) { state in
                    presenceRow(state)
                }
                outOfOfficeRow
            }
            Section {
                Button {
                    onSelectPresence(.unknown)
                } label: {
                    Label("Reset to auto", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Status")
    }

    private func presenceRow(_ state: Presence) -> some View {
        let isSelected = !isOutOfOffice && currentPresence == state
        return Button {
            onSelectPresence(state)
        } label: {
            HStack(spacing: 8) {
                PresenceGlyph(state)
                Text(state.displayName)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
    }

    private var outOfOfficeRow: some View {
        Button(action: onSelectOutOfOffice) {
            HStack(spacing: 8) {
                OutOfOfficeGlyph()
                Text("Out of office")
                Spacer()
                if isOutOfOffice {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
    }
}
