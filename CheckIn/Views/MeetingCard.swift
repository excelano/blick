// MeetingCard.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

struct MeetingCard: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onRsvp: (MeetingResponse) -> Void
    let onConflictTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                // Three-row pattern shared with the watch glance,
                // watch rectangular widget, and iPhone widget:
                // calendar icon + time range, then subject, then the
                // countdown (or "soon" / "now"). Calendar tints orange
                // alongside the countdown once the meeting is imminent
                // or live.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let highlight = meetingIsLive(start: meeting.start, referenceDate: context.date)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundStyle(highlight ? .orange : Brand.accent)
                            Text(meetingTimeRange(start: meeting.start, end: meeting.end))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.textMuted)
                            Spacer()
                        }
                        Text(meeting.subject)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        HStack(spacing: 12) {
                            Text(untilTime(meeting.start, referenceDate: context.date))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(highlight ? .orange : Brand.accent)
                            if !meeting.organizer.isEmpty {
                                Text("with \(meeting.organizer)")
                                    .font(.subheadline)
                                    .foregroundStyle(Brand.textMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, meeting.hasConflict ? 6 : 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Join meeting in Teams")

            if meeting.hasConflict {
                Button(action: onConflictTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Overlaps another meeting")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }

            switch meeting.responseStatus {
            case .notResponded:
                rsvpRow
            case .accepted, .tentativelyAccepted, .declined:
                respondedPill
            case .none, .organizer:
                EmptyView()
            }
        }
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rsvpRow: some View {
        RsvpRow(onRsvp: onRsvp)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private var respondedPill: some View {
        if let label = meeting.responseStatus.displayLabel {
            HStack {
                RespondedPill(label: label, style: .filled(Brand.bg))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var accessibilityLabel: String {
        // The card renders both the next meeting and the in-progress
        // "active" meeting, so don't announce "Next meeting" once it has
        // started.
        let lead = meetingInProgress(start: meeting.start, referenceDate: .now)
            ? "Current meeting"
            : "Next meeting"
        var parts = [lead, meeting.subject, untilTime(meeting.start, referenceDate: .now)]
        if !meeting.organizer.isEmpty { parts.append("with \(meeting.organizer)") }
        return parts.joined(separator: ", ")
    }
}
