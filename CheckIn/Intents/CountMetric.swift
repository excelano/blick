// CountMetric.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// The inbox count a user can ask CheckIn to read back from a shortcut.
/// Each maps to a number CheckIn already holds in its in-memory summary
/// after a refresh, so the spoken answer matches what the panel shows.
enum CountMetric: String, AppEnum {
    case unreadEmails
    case unreadChats
    case remainingMeetings
    case unreadMessages

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Count"
    }

    static var caseDisplayRepresentations: [CountMetric: DisplayRepresentation] {
        [
            .unreadEmails: "Unread Emails",
            .unreadChats: "Unread Chats",
            .remainingMeetings: "Remaining Meetings Today",
            .unreadMessages: "Unread Messages",
        ]
    }
}
