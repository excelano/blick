// RsvpButton.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
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
    /// Nil = filled pill (used inside dark-card contexts like meeting
    /// card and conflict-resolution sheet, where a lighter `Brand.bg`
    /// fill contrasts with the card background). Non-nil = transparent
    /// fill with a stroke in this color (used on the main app
    /// background where a fill would either disappear or feel heavy).
    var outlineColor: Color? = nil
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
            .background(Capsule().fill(fillColor))
            .foregroundStyle(.white)
            .overlay {
                if let outlineColor {
                    Capsule().strokeBorder(outlineColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        if isCurrentResponse { return Brand.accent.opacity(0.25) }
        return outlineColor == nil ? Brand.bg : Color.clear
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
