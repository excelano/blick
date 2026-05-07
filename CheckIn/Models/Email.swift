// Email.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Email: Identifiable {
    let id: String        // Graph API message ID
    let subject: String
    let from: String      // display name
    let preview: String   // bodyPreview
    let received: Date
}
