// RsvpButton.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Shared RSVP capsule button used by both `MeetingCard` (un-responded
/// state — all three buttons, none tinted) and `ConflictMeetingRow`
/// (current state tinted so the user can see what they previously
/// selected). The `label` is optional because `MeetingCard` uses an
/// icon-only decline button to save space.
struct RsvpButton: View {
    let response: MeetingResponse
    let label: String?
    let icon: String
    var isCurrentResponse: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                if let label {
                    Text(label).font(.subheadline.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isCurrentResponse ? Brand.accent.opacity(0.25) : Brand.bg)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch response {
        case .accepted: return "Accept meeting"
        case .tentativelyAccepted: return "Tentatively accept meeting"
        case .declined: return "Decline meeting"
        case .none, .notResponded, .organizer:
            // RsvpButton is only constructed with the three responseable
            // cases; a meaningful fallback keeps VoiceOver from reading
            // an empty string if the invariant ever breaks.
            return "RSVP option"
        }
    }
}
