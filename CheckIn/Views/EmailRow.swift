// EmailRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct EmailRow: View {
    let email: Email
    /// Set when this email is a meeting invitation AND the underlying
    /// meeting is in our current summary window. Drives the inline
    /// RSVP buttons and the subject-line conflict triangle. Nil for
    /// everything else.
    let matchingMeeting: Meeting?
    let onTap: () -> Void
    let onRsvp: (MeetingResponse) -> Void
    /// Called when the user taps the orange conflict triangle on the
    /// subject line. SummaryView routes this to its existing conflict-
    /// resolution sheet so the email surface uses the same flow as
    /// the "Later today" rows.
    let onConflictTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area: previewable email body. Uses .onTapGesture
            // instead of an outer Button so the nested triangle Button
            // can take its own tap reliably — nested SwiftUI Buttons
            // have inconsistent behavior across iOS versions.
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope")
                    .foregroundStyle(Brand.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(email.from).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if email.isFlagged {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Flagged")
                        }
                        Spacer()
                        Text(relativeTime(email.received))
                            .font(.caption)
                            .foregroundStyle(Brand.textMuted)
                    }
                    subjectLine
                    if !email.preview.isEmpty {
                        Text(email.preview)
                            .font(.body)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Preview message")
            .accessibilityAddTraits(.isButton)

            if let meeting = matchingMeeting {
                meetingInfoRow(for: meeting)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                switch meeting.responseStatus {
                case .notResponded:
                    rsvpRow
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                case .accepted, .tentativelyAccepted, .declined:
                    respondedPill(for: meeting)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                case .none, .organizer:
                    EmptyView()
                }
            }
        }
    }

    /// Subject text with the conflict triangle right-justified on the
    /// same row when this invite's meeting overlaps another. Placing
    /// the triangle here puts it close to the subject (its natural
    /// grouping) and far from the Decline button on the RSVP row.
    private var subjectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(email.subject)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(2)
            if matchingMeeting?.hasConflict == true {
                Spacer(minLength: 6)
                Button(action: onConflictTap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }
        }
    }

    /// Date + time only. The conflict indicator has moved up to the
    /// subject line so the user's finger isn't near the Decline RSVP
    /// button when tapping to resolve a conflict.
    private func meetingInfoRow(for meeting: Meeting) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.footnote)
            Text(formatMeetingTime(meeting.start))
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Brand.textMuted)
    }

    /// Non-interactive status pill shown in place of the RSVP buttons
    /// when the user has already responded (typically because they
    /// RSVP'd from another client and the invite email hasn't been
    /// cleared yet). Mirrors `MeetingCard`'s responded-pill style but
    /// uses the darker `Brand.bgDarker` shade so it stands out against
    /// the main view background instead of the meeting card.
    @ViewBuilder
    private func respondedPill(for meeting: Meeting) -> some View {
        if let label = meeting.responseStatus.displayLabel {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Brand.bgDarker)
                    .clipShape(Capsule())
                Spacer()
            }
        }
    }

    private var rsvpRow: some View {
        HStack(spacing: 8) {
            RsvpButton(response: .accepted, label: "Accept", icon: "checkmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.accepted)
            }
            RsvpButton(response: .tentativelyAccepted, label: "Maybe", icon: "questionmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.tentativelyAccepted)
            }
            RsvpButton(response: .declined, label: nil, icon: "xmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.declined)
            }
        }
    }

    private var accessibilityLabel: String {
        let flagPrefix = email.isFlagged ? "Flagged email" : "Email"
        let invitePrefix = matchingMeeting != nil ? "Meeting invitation" : flagPrefix
        return "\(invitePrefix) from \(email.from): \(email.subject)"
    }
}
