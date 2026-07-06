// BrowseListSupport.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// Shared building blocks for the full-screen browse lists (EmailListView,
/// ChatListView) reached from the summary's section headers. They share the
/// same chrome, the same loading/empty/error ladder, and the same preview-sheet
/// presentation; keeping those here stops the two screens from drifting.

/// Centered container for a browse list's loading / empty / error content.
struct MessageListStatus<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            Spacer(minLength: 80)
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

/// The loading → error → empty → content ladder shared by the email inbox,
/// email search, and chat browse lists. `isLoading` is consulted only while
/// `items` is empty, and `failed` takes precedence over a spinner, so a fetch
/// that fails from empty shows the error rather than a stuck spinner.
struct BrowseListContent<Item, Rows: View>: View {
    let items: [Item]
    let isLoading: Bool
    let failed: Bool
    let failedText: String
    let emptyText: String
    @ViewBuilder let rows: ([Item]) -> Rows

    var body: some View {
        if !items.isEmpty {
            rows(items)
        } else if failed {
            MessageListStatus {
                Text(failedText)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        } else if isLoading {
            MessageListStatus { ProgressView().tint(Brand.accent) }
        } else {
            MessageListStatus {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(Brand.textMuted)
            }
        }
    }
}

extension View {
    /// Shared dark-themed chrome for a browse list inside a NavigationStack:
    /// the Brand background, an inline title, a Brand-accent Done button, and
    /// the Brand toolbar.
    func browseListChrome(title: String, onClose: @escaping () -> Void) -> some View {
        self
            .background(Brand.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .foregroundStyle(Brand.accent)
                }
            }
            .toolbarBackground(Brand.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Present the shared message preview over a browse list. `onDismiss` lets
    /// the list sync the tapped row's read state once the preview closes.
    func messagePreviewSheet(inbox: Inbox,
                             target: Binding<MessagePreviewTarget?>,
                             onDismiss: @escaping () -> Void) -> some View {
        sheet(item: target, onDismiss: onDismiss) { resolved in
            MessagePreviewSheet(inbox: inbox, target: resolved,
                                onClose: { target.wrappedValue = nil })
        }
    }
}
