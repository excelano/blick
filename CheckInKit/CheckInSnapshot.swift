// CheckInSnapshot.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Snapshot of CheckIn state written to the App Group on every refresh,
/// for the widget and Control Center controls to read. Trimmed to just
/// what those surfaces can render — they can't authenticate or call
/// Graph, so anything not in this struct is invisible to them.
///
/// Lives in CheckInKit so the app, the widget extension, and any future
/// surface share one definition instead of byte-identical copies.
public struct CheckInSnapshot: Codable {
    /// When the main app last refreshed and wrote this snapshot.
    public let updatedAt: Date
    /// Subject of the next meeting today, or nil if none remain.
    public let nextMeetingSubject: String?
    /// Start time of the next meeting, or nil if none remain.
    public let nextMeetingStart: Date?
    /// Organizer name for the next meeting (drives the "with X" line).
    public let nextMeetingOrganizer: String?
    /// Teams join URL for the next meeting (drives the Join pill).
    /// Nil for events without an online meeting attached.
    public let nextMeetingJoinUrl: String?
    /// Number of unread emails in the inbox (total, not just the visible ones).
    public let unreadEmailCount: Int
    /// Number of pending Teams chats waiting on a reply.
    public let chatCount: Int
    /// Last-known Microsoft 365 presence, so controls can show the
    /// current state without a Graph call.
    public let presence: Presence
    /// Whether Outlook automatic replies (Out of Office) are on, so the
    /// OOO control can reflect live state.
    public let isOutOfOffice: Bool

    public init(
        updatedAt: Date,
        nextMeetingSubject: String?,
        nextMeetingStart: Date?,
        nextMeetingOrganizer: String?,
        nextMeetingJoinUrl: String?,
        unreadEmailCount: Int,
        chatCount: Int,
        presence: Presence,
        isOutOfOffice: Bool
    ) {
        self.updatedAt = updatedAt
        self.nextMeetingSubject = nextMeetingSubject
        self.nextMeetingStart = nextMeetingStart
        self.nextMeetingOrganizer = nextMeetingOrganizer
        self.nextMeetingJoinUrl = nextMeetingJoinUrl
        self.unreadEmailCount = unreadEmailCount
        self.chatCount = chatCount
        self.presence = presence
        self.isOutOfOffice = isOutOfOffice
    }

    /// Identifier shared between the main app and the widget extension
    /// for the App Group container both can read/write.
    public static let appGroupIdentifier = "group.com.excelano.checkin"
    /// Key inside the App Group's UserDefaults where the encoded
    /// snapshot is stored.
    public static let userDefaultsKey = "snapshot"
}
