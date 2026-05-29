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
                .foregroundStyle(.white, .green)
        case .busy:
            // Both palette slots set to .red so the red value renders
            // through the same pipeline as DND's white-on-red palette,
            // keeping the two reds visually identical.
            Image(systemName: "circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .red)
        case .doNotDisturb:
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        case .beRightBack, .away:
            Image(systemName: "clock.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow)
        case .offline:
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .gray)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.gray)
        }
    }
}
