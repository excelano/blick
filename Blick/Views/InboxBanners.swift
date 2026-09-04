// InboxBanners.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickKit
import SwiftUI

/// The floating undo and error banners, anchored to the bottom of whichever
/// screen the user is on. `Inbox` owns the state; this only renders it.
///
/// Shared because the banners were the summary's alone at first, and an
/// archive from the full Email list played out behind that sheet: the row
/// vanished, the eight-second undo window expired unseen, and the action
/// looked irreversible. Any screen that files or bulk-edits mail overlays
/// this so the banner appears where the action happened.
///
/// `onUndone` runs after a successful undo so a screen holding its own copy
/// of the rows (the browse list) can bring the restored message back; the
/// summary's rows come from `Inbox` and need nothing.
struct InboxBanners: View {
    var inbox: Inbox
    var onUndone: () async -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            transientErrorBanner
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.25), value: inbox.transientMessage)
            undoBanner
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .animation(.easeInOut(duration: 0.25), value: inbox.pendingUndo?.summary)
        }
    }

    @ViewBuilder
    private var transientErrorBanner: some View {
        if let message = inbox.transientMessage {
            let isError = message.kind == .error
            HStack(spacing: 12) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(isError ? .orange : Brand.accent)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    inbox.dismissTransientMessage()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textMuted)
                }
                .accessibilityLabel(isError ? "Dismiss error" : "Dismiss message")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.bgDarker)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let action = inbox.pendingUndo {
            HStack(spacing: 12) {
                Text(action.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Undo") {
                    Task { await inbox.performUndo(); await onUndone() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.accent)
                Button {
                    inbox.dismissUndo()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textMuted)
                }
                .accessibilityLabel("Dismiss undo")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.bgDarker)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension View {
    /// Overlay the undo and error banners on a full-screen list.
    func inboxBanners(_ inbox: Inbox, onUndone: @escaping () async -> Void = {}) -> some View {
        overlay { InboxBanners(inbox: inbox, onUndone: onUndone) }
    }
}
