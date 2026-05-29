// SummaryDetailPane.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// Detail column for the iPad (regular-width) split layout. Renders the
/// selected chat or email by reusing `MessagePreviewSheet`. The
/// `.id(target.id)` gives each selection a fresh view identity so the
/// reused sheet's `.task` re-runs (reloading the email body, auto-marking
/// read) and its `@State` resets between selections. Shows a placeholder
/// when nothing is selected.
struct SummaryDetailPane: View {
    var inbox: Inbox
    let target: MessagePreviewTarget?
    /// Forwarded to `MessagePreviewSheet` so RSVP / Mark Unread / Reply Sent
    /// clear the selection back to the placeholder. SwiftUI's
    /// `@Environment(\.dismiss)` is a no-op in this split-view detail
    /// context, which is why the parent has to thread the action through.
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            if let target {
                MessagePreviewSheet(inbox: inbox, target: target, onClose: onClose)
                    .id(target.id)
            } else {
                placeholder
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.largeTitle)
                .foregroundStyle(Brand.textMuted)
            Text("Select a message to read it here")
                .font(.title3)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
