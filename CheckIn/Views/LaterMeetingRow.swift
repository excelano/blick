// LaterMeetingRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

struct LaterMeetingRow: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onConflictTap: () -> Void

    var body: some View {
        // Mirror the watch glance's "live" treatment on the Later Today
        // rows: once a meeting is within the imminent window or already
        // started, the calendar icon and time tint orange. SummaryView
        // re-renders this list every 30 seconds via its clockTick, so
        // the recolor takes effect without a refresh.
        let live = meeting.start <= Date()
            || isMeetingImminent(meeting.start, referenceDate: Date())
        let accent = live ? Color.orange : Brand.accent
        return HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundStyle(accent)
                        .frame(width: 20)
                    Text(meetingTimeRange(start: meeting.start, end: meeting.end))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(meeting.subject)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(meetingTimeRange(start: meeting.start, end: meeting.end)): \(meeting.subject)")
            .accessibilityHint("Join meeting in Teams")

            if meeting.hasConflict {
                Button(action: onConflictTap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
