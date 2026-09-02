// LaterMeetingRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// One compact meeting row: calendar icon, time range, subject, and a
/// conflict triangle when the meeting overlaps another. Used by the
/// summary's "Later today" section and by the agenda screen, which adds
/// the `isPast` dimming for meetings earlier in the day.
struct LaterMeetingRow: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onConflictTap: () -> Void
    /// Dims the row for a meeting that has already ended. The agenda spans
    /// whole days and so shows the past; the summary never does, which is
    /// why this defaults off.
    var isPast: Bool = false

    /// A meeting with no `joinUrl` isn't an online meeting, so there is
    /// nothing for a tap to open. Rendering it as plain content instead of
    /// a Button keeps the row from advertising an action it can't perform.
    private var isJoinable: Bool { meeting.joinUrl != nil }

    /// An invitation the user hasn't answered yet. Worth surfacing because
    /// the compact row has no RSVP buttons — the actions live in the
    /// long-press menu — so without a marker an unanswered invite looks
    /// exactly like an accepted one. Suppressed for meetings that have
    /// already ended, where the question is moot.
    private var needsReply: Bool {
        !isPast && meeting.responseStatus == .notResponded
    }

    var body: some View {
        // Mirror the watch glance's "live" treatment on the Later Today
        // rows: once a meeting is within the imminent window or already
        // started, the calendar icon and time tint orange. SummaryView
        // re-renders this list every 30 seconds via its clockTick, so
        // the recolor takes effect without a refresh.
        let live = !isPast && meetingIsLive(start: meeting.start, referenceDate: Date())
        let accent = live ? Color.orange : Brand.accent
        return HStack(spacing: 12) {
            if isJoinable {
                Button(action: onTap) {
                    content(accent: accent)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Join meeting in Teams")
            } else {
                content(accent: accent)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
            }

            if needsReply {
                RespondedPill(label: "Needs reply",
                              style: .outlined(Brand.accent),
                              textColor: Brand.accent)
                    // Folded into the row's own label below, so VoiceOver
                    // reads one phrase instead of two fragments.
                    .accessibilityHidden(true)
            }

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
        .opacity(isPast ? 0.45 : 1)
    }

    private func content(accent: Color) -> some View {
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

    private var accessibilityLabel: String {
        let base = "\(meetingTimeRange(start: meeting.start, end: meeting.end)): \(meeting.subject)"
        return needsReply ? "\(base). Needs reply" : base
    }
}
