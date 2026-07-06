// ChatMessage.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    /// Graph chat id (the thread, not the individual message). Used to
    /// post a reply via `POST /me/chats/{chatId}/messages`. Optional
    /// because some legacy chats don't populate it — reply is disabled
    /// for those.
    let chatId: String?
    let topic: String
    let from: String
    let preview: String
    let sent: Date
    /// Other people in the thread besides you and the sender. Empty for
    /// 1:1 chats.
    let otherParticipants: [String]
    /// Graph-supplied `https://teams.microsoft.com/l/chat/...` URL. iOS
    /// routes it to the Teams app when installed. Optional because legacy
    /// chats and some tenants don't populate it.
    let webUrl: String?
    /// Always false in the unread pending list; meaningful in the full chat
    /// browse, which carries read and unread threads side by side. `var` so a
    /// browse row can flip in place on mark read/unread without changing its
    /// identity (`id` is a per-instance UUID, so reconstructing would reorder).
    var isRead: Bool

    init(chatId: String?, topic: String, from: String, preview: String, sent: Date,
         otherParticipants: [String], webUrl: String?, isRead: Bool = false) {
        self.chatId = chatId
        self.topic = topic
        self.from = from
        self.preview = preview
        self.sent = sent
        self.otherParticipants = otherParticipants
        self.webUrl = webUrl
        self.isRead = isRead
    }
}
