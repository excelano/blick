// CheckInSnapshot.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import WidgetKit

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

    /// Decode the snapshot last written to an App Group, or nil if none
    /// is stored yet (or it can't be opened/decoded). The single read
    /// path shared by the widget timeline, the widget's status actions,
    /// the Control Center value providers, and the app's intent-driven
    /// patch. Watch surfaces pass `watchAppGroupIdentifier` to read the
    /// snapshot pushed from the phone over WatchConnectivity.
    public static func loadFromAppGroup(suite: String = appGroupIdentifier) -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: suite),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
    }

    /// Encode and write the snapshot to an App Group. Returns `true` on
    /// success so callers can log a failure with their own logger. The
    /// single write path shared by the app's refresh, the app's
    /// intent-driven patch, the widget's status actions, and the watch's
    /// session receiver (which passes `watchAppGroupIdentifier`).
    @discardableResult
    public func saveToAppGroup(suite: String = appGroupIdentifier) -> Bool {
        guard let data = try? JSONEncoder().encode(self),
              let defaults = UserDefaults(suiteName: suite) else {
            return false
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
        return true
    }

    /// Reload the widget timelines and (iOS 18+) the Out-of-Office Control
    /// Center toggle. Surfaces drive themselves from the App Group snapshot,
    /// so a reload after a write is what makes a change visible.
    public static func reloadStatusSurfaces() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlKind.outOfOffice)
        }
        #endif
    }

    /// Patch the last-written snapshot's presence/OOO fields and reload
    /// surfaces. Used after an intent-driven mutation when the caller
    /// doesn't have a full summary to rebuild the snapshot from — it
    /// updates the fields the surfaces care about and leaves the rest
    /// alone. Reloads even if no snapshot was found, so an empty App
    /// Group at least nudges the surfaces to refetch.
    public static func patchAndReload(presence: Presence, isOutOfOffice: Bool) {
        if let existing = loadFromAppGroup() {
            existing
                .settingStatus(presence: presence, isOutOfOffice: isOutOfOffice)
                .saveToAppGroup()
        }
        reloadStatusSurfaces()
    }

    /// Default auto-reply text used only when Graph reports an empty
    /// message at OOO toggle-on time. Anything the user previously set
    /// (via Outlook web, for instance) is preserved.
    public static let defaultOutOfOfficeMessage =
        "I'm currently out of the office and will respond when I return."

    /// Identifier shared between the main app and the widget extension
    /// for the App Group container both can read/write.
    public static let appGroupIdentifier = "group.com.excelano.checkin"
    /// Identifier shared between the watch app and its widget extension.
    /// Distinct from the phone's group because App Groups don't sync
    /// across devices — the watch keeps its own copy of the snapshot
    /// after `WatchSessionReceiver` decodes the WatchConnectivity push.
    public static let watchAppGroupIdentifier = "group.com.excelano.checkin.watch"
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
