// WatchStandalone.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickGraph
import BlickKit
import Foundation
import WatchConnectivity

/// What the watch does for itself, against Graph with its own token, when the
/// phone is out of reach. `isAvailable` is true only after the user has signed
/// the watch in from Settings on the iPhone, so without that step none of this
/// runs and the watch stays on the phone-relayed tier.
enum WatchStandalone {
    private static let listCap = 15
    private static let browseCap = 40

    static var isAvailable: Bool {
        get async { await WatchTokenProvider.shared.isSignedIn }
    }

    private static var core: GraphCore {
        GraphCore(tokenProvider: WatchTokenProvider.shared)
    }

    static func snapshot() async throws -> BlickSnapshot {
        let core = core
        let fetched = try await core.fetchSnapshot()
        let emails = try await core.fetchWatchEmails(unreadOnly: true, top: listCap)
        let chats = try await core.fetchWatchChats(unreadOnly: true, top: listCap)
        return BlickSnapshot(
            updatedAt: fetched.updatedAt,
            nextMeetingSubject: fetched.nextMeetingSubject,
            nextMeetingStart: fetched.nextMeetingStart,
            nextMeetingEnd: fetched.nextMeetingEnd,
            nextMeetingOrganizer: fetched.nextMeetingOrganizer,
            nextMeetingJoinUrl: fetched.nextMeetingJoinUrl,
            unreadEmailCount: fetched.unreadEmailCount,
            chatCount: fetched.chatCount,
            presence: fetched.presence,
            isOutOfOffice: fetched.isOutOfOffice,
            laterMeetings: fetched.laterMeetings,
            topEmails: emails,
            topChats: chats
        )
    }

    static func recentEmails() async throws -> [SnapshotEmail] {
        try await core.fetchWatchEmails(unreadOnly: false, top: browseCap)
    }

    static func recentChats() async throws -> [SnapshotChat] {
        try await core.fetchWatchChats(unreadOnly: false, top: browseCap)
    }

    static func emailText(id: String) async throws -> String {
        try await core.fetchEmailText(id: id)
    }

    static func chatText(id: String) async throws -> String {
        let identity = try await chatIdentity()
        return try await core.fetchChatText(id: id, currentUserID: identity.userID)
    }

    static func replyToEmail(id: String, text: String) async throws {
        try await core.replyAll(emailID: id, text: text)
    }

    static func replyToChat(id: String, text: String) async throws {
        try await core.sendChatReply(chatID: id, text: text)
    }

    static func setPresence(_ presence: Presence, wasOutOfOffice: Bool) async throws {
        let core = core
        if wasOutOfOffice { try? await core.disableAutomaticReplies() }
        let registration = await WatchTokenProvider.shared.registration
        let result = try await core.applyPreferredPresence(
            presence,
            sessionId: registration?.clientID ?? PublishedConfig.clientID,
            store: PreferredPresenceStore(suite: BlickSnapshot.watchAppGroupIdentifier)
        )
        guard result.honored else { throw WatchAuthError.rejected(code: "presence_not_honored", description: "") }
        WCSession.default.transferUserInfo([WatchPresencePinWire.reportKey: WatchPresencePinWire.report(for: presence)])
    }

    static func setOutOfOffice(_ on: Bool) async throws {
        if on {
            try await core.enableAutomaticReplies(defaultMessage: BlickSnapshot.defaultOutOfOfficeMessage)
        } else {
            try await core.disableAutomaticReplies()
        }
    }

    /// Runs one fire-and-forget action from the same payload the phone relay
    /// carries, so a queued action and a direct one share a shape.
    static func perform(_ payload: [String: Any], wasOutOfOffice: Bool) async throws {
        typealias Receiver = WatchSessionReceiver
        guard let raw = payload[Receiver.WireKey.actionKind] as? String,
              let kind = Receiver.ActionKind(rawValue: raw) else { return }
        let id = payload[Receiver.WireKey.id] as? String
        let core = core
        switch kind {
        case .setPresence:
            guard let raw = payload[Receiver.WireKey.presence] as? String, let presence = Presence(rawValue: raw) else { return }
            try await setPresence(presence, wasOutOfOffice: wasOutOfOffice)
        case .setOutOfOffice:
            try await setOutOfOffice(payload[Receiver.WireKey.outOfOfficeOn] as? Bool ?? false)
        case .markEmailRead, .markEmailUnread:
            guard let id else { return }
            try await core.setEmailRead(id: id, isRead: kind == .markEmailRead)
        case .markChatRead, .markChatUnread:
            guard let id else { return }
            try await core.setChatRead(id: id, isRead: kind == .markChatRead, identity: try await chatIdentity())
        case .setEmailFlagged:
            guard let id, let flagged = payload[Receiver.WireKey.flagged] as? Bool else { return }
            try await core.setEmailFlagged(id: id, flagged: flagged)
        default:
            return
        }
    }

    private static func chatIdentity() async throws -> ChatIdentity {
        guard let identity = await WatchTokenProvider.shared.chatIdentity else { throw WatchAuthError.notSignedIn }
        return identity
    }
}
