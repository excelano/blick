// ComposerBodyStyle.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

extension View {
    /// Shared visual treatment for the plain-text body `TextEditor` used by
    /// both the reply composer and the new-message composer, so the two
    /// surfaces stay visually identical instead of drifting. Instance-specific
    /// modifiers (focus, padding, disabled) stay at the call site.
    func composerBodyStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Brand.bg)
            .font(.body)
            .foregroundStyle(.white)
            .tint(Brand.accent)
    }
}
