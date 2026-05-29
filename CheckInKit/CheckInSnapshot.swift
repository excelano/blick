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

    /// A copy with only the presence and Out-of-Office fields replaced.
    /// Lets the app patch the last-written snapshot after an intent
    /// mutation — including when it was background-launched and has no
    /// fresh summary to build a full snapshot from.
    public func settingStatus(presence: Presence, isOutOfOffice: Bool) -> CheckInSnapshot {
        CheckInSnapshot(
            updatedAt: updatedAt,
            nextMeetingSubject: nextMeetingSubject,
            nextMeetingStart: nextMeetingStart,
            nextMeetingOrganizer: nextMeetingOrganizer,
            nextMeetingJoinUrl: nextMeetingJoinUrl,
            unreadEmailCount: unreadEmailCount,
            chatCount: chatCount,
            presence: presence,
            isOutOfOffice: isOutOfOffice
        )
    }

    /// Decode the snapshot the app last wrote to the App Group, or nil if
    /// none is stored yet (or it can't be opened/decoded). The single read
    /// path shared by the widget timeline, the widget's status actions, the
    /// Control Center value providers, and the app's intent-driven patch.
    public static func loadFromAppGroup() -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
    }

    /// Identifier shared between the main app and the widget extension
    /// for the App Group container both can read/write.
    public static let appGroupIdentifier = "group.com.excelano.checkin"
    /// Key inside the App Group's UserDefaults where the encoded
    /// snapshot is stored.
    public static let userDefaultsKey = "snapshot"
    /// App Group keys for the MSAL config the widget needs to build an
    /// instance matching the app's, so it can read the shared token cache.
    /// The app writes these; a custom Azure registration set in the app's
    /// private UserDefaults wouldn't otherwise be visible to the extension.
    public static let effectiveClientIDKey = "effectiveClientID"
    public static let effectiveAuthorityKey = "effectiveAuthority"
}
