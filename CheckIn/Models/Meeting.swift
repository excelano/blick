// Meeting.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Meeting: Identifiable {
    let id = UUID()
    let subject: String
    let organizer: String
    let location: String
    let start: Date
    let end: Date
    let isOnline: Bool
    let attendees: [String]

    /// Graph-supplied Teams join URL. Populated from `onlineMeeting.joinUrl`
    /// when the event is an online meeting. iOS routes the URL to Teams when
    /// installed. Nil when the event has no online meeting attached.
    let joinUrl: String?
}
