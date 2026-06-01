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

/// The Accept / Maybe / Decline triplet shared by the meeting card, email
/// row, message-preview sheet, and conflict-resolution sheet. The surfaces
/// differ only in the button chrome (`outlineColor`), whether Decline shows
/// a label, and whether the current response is highlighted — all parameters
/// here, so the three-button layout lives in one place.
struct RsvpRow: View {
    /// nil = filled pills (dark-card contexts); non-nil = outlined in this color.
    var outlineColor: Color? = nil
    /// nil = icon-only Decline (used where horizontal space is tight).
    var declineLabel: String? = nil
    /// When set, the matching button is highlighted as the current response.
    var currentResponse: MeetingResponse? = nil
    let onRsvp: (MeetingResponse) -> Void

    var body: some View {
        HStack(spacing: 8) {
            RsvpButton(response: .accepted, label: "Accept", icon: "checkmark",
                       isCurrentResponse: currentResponse == .accepted,
                       outlineColor: outlineColor) { onRsvp(.accepted) }
            RsvpButton(response: .tentativelyAccepted, label: "Maybe", icon: "questionmark",
                       isCurrentResponse: currentResponse == .tentativelyAccepted,
                       outlineColor: outlineColor) { onRsvp(.tentativelyAccepted) }
            RsvpButton(response: .declined, label: declineLabel, icon: "xmark",
                       isCurrentResponse: currentResponse == .declined,
                       outlineColor: outlineColor) { onRsvp(.declined) }
        }
    }
}

/// Non-interactive capsule showing a meeting's responded state ("Accepted",
/// "Removed", …). Filled on dark-card surfaces, outlined on the main app
/// background — the chrome is the only thing that differs, so callers pick a
/// `style` and the text/padding/shape live here.
struct RespondedPill: View {
    enum Style {
        case filled(Color)
        case outlined(Color)
    }
    let label: String
    let style: Style

    var body: some View {
        let base = Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(Brand.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        switch style {
        case .filled(let color):
            base.background(color).clipShape(Capsule())
        case .outlined(let color):
            base.overlay { Capsule().strokeBorder(color, lineWidth: 1) }
        }
    }
}
