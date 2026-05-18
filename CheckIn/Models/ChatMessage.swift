// ChatMessage.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let chatID: String
    let topic: String
    let from: String
    let preview: String
    let sent: Date

    /// Graph-supplied `https://teams.microsoft.com/l/chat/...` URL. iOS
    /// routes it to the Teams app when installed, landing on the exact
    /// chat rather than the chat list. Optional because legacy chats and
    /// some tenants don't always populate it.
    let webUrl: String?
}
