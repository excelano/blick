// ChatListView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The full chat list, reached by tapping the summary's Chats header. Browses
/// recent chats — read and unread, newest first — with more room than the
/// glance, each opening the preview on tap. No search in v1 (Graph's chat
/// search is weak). Read state comes from Graph's per-user read timestamp; a
/// mark read/unread swipe flips the row in place.
struct ChatListView: View {
    var inbox: Inbox
    let onClose: () -> Void

    @State private var chats: [ChatMessage] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var previewTarget: MessagePreviewTarget?
    /// The id of the row whose preview is open, so its read state can be synced
    /// when the sheet closes (the preview auto-marks read on the server).
    @State private var openedId: UUID?

    var body: some View {
        NavigationStack {
            BrowseListContent(items: chats, isLoading: !loaded, failed: failed,
                              failedText: "Couldn't load chats. Check your connection and try again.",
                              emptyText: "No chats.") { chatList($0) }
                .browseListChrome(title: "Chats", onClose: onClose)
        }
        .task { await load() }
        .preferredColorScheme(.dark)
        .messagePreviewSheet(inbox: inbox, target: $previewTarget, onDismiss: markOpenedRead)
    }

    private func chatList(_ chats: [ChatMessage]) -> some View {
        List {
            ForEach(chats) { chat in
                ChatRow(chat: chat, onTap: { openedId = chat.id; previewTarget = .chat(chat) })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if chat.chatId != nil {
                            Button { toggleRead(chat) } label: {
                                Label(chat.isRead ? "Mark Unread" : "Mark Read",
                                      systemImage: chat.isRead ? "bubble.left.and.bubble.right" : "checkmark.bubble")
                            }
                            .tint(chat.isRead ? .blue : .green)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
    }

    private func load() async {
        do {
            chats = try await inbox.recentChats()
            loaded = true
        } catch {
            failed = true
        }
    }

    /// Toggle read/unread: flip the row optimistically, drive Graph through the
    /// browse-safe Inbox path (which keeps the glance unread-styled and in sync),
    /// and revert the row if that call fails.
    private func toggleRead(_ chat: ChatMessage) {
        let target = !chat.isRead
        setLocalRead(chat.id, target)
        Task {
            do {
                try await inbox.setChatReadFromBrowse(target, chat: chat)
            } catch {
                setLocalRead(chat.id, !target)
            }
        }
    }

    private func setLocalRead(_ id: UUID, _ isRead: Bool) {
        if let i = chats.firstIndex(where: { $0.id == id }) { chats[i].isRead = isRead }
    }

    /// A tapped chat is auto-marked read by the preview sheet on the server;
    /// reflect that on the row when the sheet closes.
    private func markOpenedRead() {
        guard let id = openedId else { return }
        openedId = nil
        setLocalRead(id, true)
    }
}
