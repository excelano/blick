// ConflictResolutionSheet.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ConflictResolutionSheet: View {
    var inbox: Inbox
    let primaryMeetingId: String

    @Environment(\.dismiss) private var dismiss
    /// IDs captured when the sheet opens. Rows render in this order from
    /// live Inbox state; ids whose meeting no longer exists (deleted)
    /// are silently skipped. Keeps the sheet stable when any meeting is
    /// removed — only that row disappears.
    @State private var trackedIds: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("These meetings overlap. Adjust your response on one or both.")
                        .font(.footnote)
                        .foregroundStyle(Brand.textMuted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    ForEach(trackedIds, id: \.self) { id in
                        if let meeting = lookupMeeting(id: id) {
                            ConflictMeetingRow(
                                meeting: meeting,
                                onRsvp: { response in
                                    Task { await inbox.respondToMeeting(response, meetingId: meeting.id) }
                                },
                                onDelete: {
                                    Task { await inbox.deleteMeeting(meetingId: meeting.id) }
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.bg)
            .navigationTitle("Overlapping meetings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
            .onAppear { initializeTrackedIds() }
        }
        .preferredColorScheme(.dark)
    }

    /// Snapshot the primary + every meeting overlapping it at open time.
    /// Subsequent renders pull live state by id, so RSVP changes flow
    /// through and deletions just drop the corresponding row.
    private func initializeTrackedIds() {
        guard trackedIds.isEmpty else { return }
        var ids = [primaryMeetingId]
        if let primary = lookupMeeting(id: primaryMeetingId) {
            let next = inbox.summary?.meeting
            let later = inbox.summary?.laterToday ?? []
            let candidates = [next].compactMap { $0 } + later
            ids += candidates
                .filter { other in
                    other.id != primary.id
                        && other.start < primary.end
                        && primary.start < other.end
                }
                .map(\.id)
        }
        trackedIds = ids
    }

    private func lookupMeeting(id: String) -> Meeting? {
        if let m = inbox.summary?.meeting, m.id == id { return m }
        return inbox.summary?.laterToday.first(where: { $0.id == id })
    }
}

struct ConflictMeetingRow: View {
    let meeting: Meeting
    let onRsvp: (MeetingResponse) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.subject)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("\(formatTimeOfDay(meeting.start)) \u{2013} \(formatTimeOfDay(meeting.end))")
                .font(.subheadline)
                .foregroundStyle(Brand.accent)
            if meeting.responseStatus.canRsvp, !meeting.organizer.isEmpty {
                Text("with \(meeting.organizer)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
            }
            if let label = meeting.responseStatus.displayLabel {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Brand.bg)
                    .clipShape(Capsule())
            }
            if meeting.responseStatus.canRsvp {
                HStack(spacing: 8) {
                    RsvpButton(response: .accepted,
                               label: "Accept",
                               icon: "checkmark",
                               isCurrentResponse: meeting.responseStatus == .accepted) {
                        onRsvp(.accepted)
                    }
                    RsvpButton(response: .tentativelyAccepted,
                               label: "Maybe",
                               icon: "questionmark",
                               isCurrentResponse: meeting.responseStatus == .tentativelyAccepted) {
                        onRsvp(.tentativelyAccepted)
                    }
                    RsvpButton(response: .declined,
                               label: "Decline",
                               icon: "xmark",
                               isCurrentResponse: meeting.responseStatus == .declined) {
                        onRsvp(.declined)
                    }
                }
            } else {
                deleteButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 4) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                Text("Delete").font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Brand.bg)
            .foregroundStyle(.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
