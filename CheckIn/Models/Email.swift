// Email.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Email: Identifiable {
    let id: String        // Graph API message ID
    let subject: String
    let from: String      // display name
    let fromAddress: String  // SMTP address; required for outlookReply deep-link
    let preview: String   // bodyPreview
    let received: Date
}
