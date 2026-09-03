// MoveToFolderSheet.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickKit
import SwiftUI

/// Destination picker for "Move to…". Fetches the mail folders on open rather
/// than holding them on `Inbox`, because filing is occasional and the list is
/// better fresh than cached — a folder made in Outlook five minutes ago should
/// be here.
///
/// Archive and Delete need no picker at all; they address Graph's well-known
/// folder names directly. This exists only for the open-ended case.
struct MoveToFolderSheet: View {
    var inbox: Inbox
    let email: Email
    let onClose: () -> Void

    @State private var folders: [MailFolder] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            BrowseListContent(
                items: folders,
                isLoading: !loaded,
                failed: failed,
                failedText: "Couldn't load your folders. Check your connection and try again.",
                emptyText: "No folders to move to."
            ) { folderList($0) }
                .browseListChrome(title: "Move to", onClose: onClose)
        }
        .task { await load() }
        .preferredColorScheme(.dark)
    }

    private func folderList(_ folders: [MailFolder]) -> some View {
        List {
            ForEach(folders) { folder in
                Button {
                    Task { await inbox.moveEmail(email, to: folder) }
                    onClose()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: folder.depth == 0 ? "folder" : "folder.badge.gearshape")
                            .foregroundStyle(Brand.accent)
                            .frame(width: 20)
                        Text(folder.displayName)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    // Children indent under their parent instead of nesting,
                    // which keeps the whole list scannable in one column.
                    .padding(.leading, CGFloat(folder.depth) * 20)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
    }

    private func load() async {
        do {
            folders = try await inbox.mailFolders()
            loaded = true
        } catch {
            failed = true
        }
    }
}
