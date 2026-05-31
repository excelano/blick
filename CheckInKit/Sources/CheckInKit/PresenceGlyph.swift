// PresenceGlyph.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// SF-Symbol icon styled to match Teams' presence palette. Shared by the
/// in-app presence menu and the widget's quick-set buttons so both
/// surfaces show the same glyph for a given state. Uses
/// `.symbolRenderingMode(.palette)` for two-tone glyphs (checkmark on
/// green, minus on red, etc.); single-tone styling would otherwise
/// render everything as the container's tint color.
public struct PresenceGlyph: View {
    private let presence: Presence

    public init(_ presence: Presence) {
        self.presence = presence
    }

    public var body: some View {
        switch presence {
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .green)
        case .busy, .doNotDisturb:
            // Busy and DND share the same minus-on-red glyph. Microsoft
            // distinguishes them by giving DND a glyph and leaving Busy
            // bare, which makes their icon set inconsistent across
            // statuses; CheckIn prefers a uniform "colored circle with
            // a glyph" treatment and relies on the adjacent label to
            // tell the two apart.
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .red)
        case .beRightBack, .away:
            Image(systemName: "clock.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow)
        case .offline:
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .gray)
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .gray)
        }
    }
}
