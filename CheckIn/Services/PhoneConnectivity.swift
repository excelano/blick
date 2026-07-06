// PhoneConnectivity.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation
import WatchConnectivity
import os

/// Phone-side WatchConnectivity link to the CheckIn watch app. Pushes the
/// status snapshot to the watch whenever the phone refreshes or mutates
/// status, and receives presence / Out-of-Office action requests from
/// the watch glance, routing them through the same Inbox entry points
/// Siri uses (`applyPresence`, `applyOutOfOffice`).
///
/// No Microsoft credentials cross this link. Payloads are an encoded
/// `CheckInSnapshot` (phone → watch) and a small action dictionary
/// (watch → phone). The phone holds the only token and runs every
/// Graph call; the watch just relays user intent.
@MainActor
final class PhoneConnectivity: NSObject {
    private let setPresence: (Presence) async throws -> Void
    private let setOutOfOffice: (Bool) async throws -> Void
    private let refresh: () async -> Void
    private let fetchEmailBody: (String) async -> String?
    private let fetchChatBody: (String) async -> String?
    private let markEmailRead: (String) async -> Void
    private let markChatRead: (String) async -> Void
    private let markEmailUnread: (String) async -> Void
    private let markChatUnread: (String) async -> Void
    private let setEmailFlagged: (String, Bool) async -> Void
    private let replyEmail: (String, String) async -> Bool
    private let replyChat: (String, String) async -> Bool
    private let fetchMoreEmails: () async -> [SnapshotEmail]
    private let fetchMoreChats: () async -> [SnapshotChat]
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "phone-connectivity")

    init(
        setPresence: @escaping (Presence) async throws -> Void,
        setOutOfOffice: @escaping (Bool) async throws -> Void,
        refresh: @escaping () async -> Void,
        fetchEmailBody: @escaping (String) async -> String?,
        fetchChatBody: @escaping (String) async -> String?,
        markEmailRead: @escaping (String) async -> Void,
        markChatRead: @escaping (String) async -> Void,
        markEmailUnread: @escaping (String) async -> Void,
        markChatUnread: @escaping (String) async -> Void,
        setEmailFlagged: @escaping (String, Bool) async -> Void,
        replyEmail: @escaping (String, String) async -> Bool,
        replyChat: @escaping (String, String) async -> Bool,
        fetchMoreEmails: @escaping () async -> [SnapshotEmail],
        fetchMoreChats: @escaping () async -> [SnapshotChat]
    ) {
        self.setPresence = setPresence
        self.setOutOfOffice = setOutOfOffice
        self.refresh = refresh
        self.fetchEmailBody = fetchEmailBody
        self.fetchChatBody = fetchChatBody
        self.markEmailRead = markEmailRead
        self.markChatRead = markChatRead
        self.markEmailUnread = markEmailUnread
        self.markChatUnread = markChatUnread
        self.setEmailFlagged = setEmailFlagged
        self.replyEmail = replyEmail
        self.replyChat = replyChat
        self.fetchMoreEmails = fetchMoreEmails
        self.fetchMoreChats = fetchMoreChats
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Push the given snapshot to the watch via
    /// `updateApplicationContext(_:)`. iOS coalesces back-to-back updates
    /// to the latest payload, so calling this on every refresh is fine —
    /// the watch always sees the most recent state, even if it was off
    /// the wrist when older updates were sent.
    func push(_ snapshot: CheckInSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("push: failed to encode snapshot")
            return
        }
        do {
            try session.updateApplicationContext([WireKey.snapshot: data])
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Push whatever snapshot is currently sitting in the App Group.
    /// Used after `CheckInSnapshot.patchAndReload(...)` updates the App
    /// Group blob from an intent that ran without a full refresh, so
    /// the watch still gets the patched presence / OOO state even when
    /// there's no fresh `summary` to rebuild a snapshot from.
    func pushFromAppGroup() {
        guard let snapshot = CheckInSnapshot.loadFromAppGroup() else { return }
        push(snapshot)
    }

    fileprivate func handleAction(_ payload: [String: Any]) {
        guard let kindRaw = payload[WireKey.actionKind] as? String,
              let kind = ActionKind(rawValue: kindRaw) else {
            logger.error("handleAction: missing or unknown kind")
            return
        }
        switch kind {
        case .setPresence:
            guard let raw = payload[WireKey.presence] as? String,
                  let presence = Presence(rawValue: raw) else {
                logger.error("handleAction(setPresence): missing or unknown presence")
                return
            }
            Task { @MainActor in
                do {
                    try await self.setPresence(presence)
                } catch {
                    self.logger.error("setPresence from watch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .setOutOfOffice:
            guard let on = payload[WireKey.outOfOfficeOn] as? Bool else {
                logger.error("handleAction(setOutOfOffice): missing on flag")
                return
            }
            Task { @MainActor in
                do {
                    try await self.setOutOfOffice(on)
                } catch {
                    self.logger.error("setOutOfOffice from watch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .refresh:
            // The watch is asking for fresh data. Run the same refresh
            // path the foreground app uses; `Inbox.refresh()` ends by
            // calling `publishStatusSnapshot()`, which the watch sees
            // arrive as the updated `updatedAt` on its end.
            Task { @MainActor in
                await self.refresh()
            }
        case .markEmailRead:
            guard let id = payload[WireKey.id] as? String else {
                logger.error("handleAction(markEmailRead): missing id")
                return
            }
            Task { @MainActor in await self.markEmailRead(id) }
        case .markChatRead:
            guard let id = payload[WireKey.id] as? String else {
                logger.error("handleAction(markChatRead): missing id")
                return
            }
            Task { @MainActor in await self.markChatRead(id) }
        case .markEmailUnread:
            guard let id = payload[WireKey.id] as? String else {
                logger.error("handleAction(markEmailUnread): missing id")
                return
            }
            Task { @MainActor in await self.markEmailUnread(id) }
        case .markChatUnread:
            guard let id = payload[WireKey.id] as? String else {
                logger.error("handleAction(markChatUnread): missing id")
                return
            }
            Task { @MainActor in await self.markChatUnread(id) }
        case .setEmailFlagged:
            guard let id = payload[WireKey.id] as? String,
                  let flagged = payload[WireKey.flagged] as? Bool else {
                logger.error("handleAction(setEmailFlagged): missing id or flag")
                return
            }
            Task { @MainActor in await self.setEmailFlagged(id, flagged) }
        case .fetchEmailBody, .fetchChatBody, .replyEmail, .replyChat,
             .fetchMoreEmails, .fetchMoreChats:
            // Data / acknowledged requests are served by `handleRequest` over
            // the reply-handler path; if one arrives without a reply handler
            // there's nowhere to return the result, so ignore it.
            break
        }
    }

    /// Handle a watch request that expects data back (a full email body or
    /// chat transcript), replying with the text or an empty dictionary on
    /// failure so the watch falls back to its snapshot preview. Non-fetch
    /// messages route to the fire-and-forget action path.
    fileprivate func handleRequest(_ payload: [String: Any],
                                   reply: @escaping ([String: Any]) -> Void) async {
        guard let kindRaw = payload[WireKey.actionKind] as? String,
              let kind = ActionKind(rawValue: kindRaw) else {
            reply([:])
            return
        }
        switch kind {
        case .fetchEmailBody, .fetchChatBody:
            guard let id = payload[WireKey.id] as? String else {
                reply([:])
                return
            }
            let body = kind == .fetchEmailBody
                ? await fetchEmailBody(id)
                : await fetchChatBody(id)
            reply(body.map { [WireKey.body: $0] } ?? [:])
        case .replyEmail, .replyChat:
            // A watch reply is a real send that needs the phone, so it comes
            // over the reply-handler path for an ack — the watch tells the
            // user "sent" or "couldn't send" rather than silently queueing.
            guard let id = payload[WireKey.id] as? String,
                  let text = payload[WireKey.text] as? String else {
                reply([WireKey.ok: false])
                return
            }
            let ok = kind == .replyEmail
                ? await replyEmail(id, text)
                : await replyChat(id, text)
            reply([WireKey.ok: ok])
        case .fetchMoreEmails:
            let items = await fetchMoreEmails()
            reply((try? JSONEncoder().encode(items)).map { [WireKey.items: $0] } ?? [:])
        case .fetchMoreChats:
            let items = await fetchMoreChats()
            reply((try? JSONEncoder().encode(items)).map { [WireKey.items: $0] } ?? [:])
        default:
            handleAction(payload)
            reply([:])
        }
    }

    enum WireKey {
        static let snapshot = "snapshot"
        static let actionKind = "kind"
        static let presence = "presence"
        static let outOfOfficeOn = "on"
        static let id = "id"
        static let body = "body"
        static let flagged = "flagged"
        static let text = "text"
        static let ok = "ok"
        static let items = "items"
    }

    enum ActionKind: String {
        case setPresence
        case setOutOfOffice
        case refresh
        case fetchEmailBody
        case fetchChatBody
        case markEmailRead
        case markChatRead
        case markEmailUnread
        case markChatUnread
        case setEmailFlagged
        case replyEmail
        case replyChat
        case fetchMoreEmails
        case fetchMoreChats
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in
                self.logger.error("activation error: \(message, privacy: .public)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleAction(message)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            await self.handleRequest(message, reply: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleAction(userInfo)
        }
    }
}
