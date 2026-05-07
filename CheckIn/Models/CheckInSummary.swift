// CheckInSummary.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct CheckInSummary {
    let meeting: Meeting?
    let emails: [Email]
    let chats: [ChatMessage]
    let emailError: String?
    let chatError: String?
    let teamsEnabled: Bool
}
