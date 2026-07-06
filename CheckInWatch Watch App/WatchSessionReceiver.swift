// WatchSessionReceiver.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit
import os

/// Watch-side WatchConnectivity link. Receives the encoded status
/// snapshot from the phone and forwards it to the glance and the watch
/// widgets. Also sends user-originated presence / Out-of-Office actions
/// back to the phone, where Inbox runs the actual Graph call.
///
/// Holds no Microsoft credentials. The snapshot it stores in the watch
/// App Group is the same non-credential status payload the iOS widget
/// already reads from the phone's App Group.
@Observable
final class WatchSessionReceiver: NSObject {
    /// Most recently received snapshot. The glance reads this directly;
    /// the watch widgets read from the App Group (which this class
    /// keeps in sync with `snapshot`).
    private(set) var snapshot: CheckInSnapshot?
    /// True once the WCSession has activated. Until then we can't
    /// reliably check `isReachable` or queue user-info.
    private(set) var isActivated: Bool = false

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin.watch", category: "session-receiver")

    override init() {
        super.init()
        // Load any previously-pushed snapshot so the glance has something
        // to show on cold launch before a fresh push arrives.
        let initial = CheckInSnapshot.loadFromAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
        Task { @MainActor in self.snapshot = initial }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Send a presence change to the phone. Live message when reachable,
    /// `transferUserInfo` fallback otherwise (queued until the next
    /// reachable connection). The phone is the only side that talks to
    /// Graph; the canonical confirmation is the snapshot push that comes
    /// back after the mutation.
    func sendPresence(_ presence: Presence) {
        send([
            WireKey.actionKind: ActionKind.setPresence.rawValue,
            WireKey.presence: presence.rawValue
        ])
    }

    /// Send an Out-of-Office toggle to the phone. Same delivery
    /// semantics as `sendPresence`.
    func sendOutOfOffice(_ on: Bool) {
        send([
            WireKey.actionKind: ActionKind.setOutOfOffice.rawValue,
            WireKey.outOfOfficeOn: on
        ])
    }

    /// Tell the phone the user read an email on the watch (opening it there
    /// marks it read, as on the phone). Fire-and-forget: queued via
    /// `transferUserInfo` if the phone is away, and the phone re-pushes a
    /// snapshot so the unread list drops it.
    func sendMarkEmailRead(id: String) {
        send([WireKey.actionKind: ActionKind.markEmailRead.rawValue, WireKey.id: id])
    }

    /// Tell the phone the user read a chat on the watch. Same semantics.
    func sendMarkChatRead(id: String) {
        send([WireKey.actionKind: ActionKind.markChatRead.rawValue, WireKey.id: id])
    }

    /// Flip an email back to unread from the wrist. Fire-and-forget, like the
    /// mark-read path; the Graph state changes right away and the phone's list
    /// reconciles on its next refresh.
    func sendMarkEmailUnread(id: String) {
        send([WireKey.actionKind: ActionKind.markEmailUnread.rawValue, WireKey.id: id])
    }

    /// Flip a chat back to unread from the wrist. Same semantics.
    func sendMarkChatUnread(id: String) {
        send([WireKey.actionKind: ActionKind.markChatUnread.rawValue, WireKey.id: id])
    }

    /// Flag or unflag an email from the wrist. Fire-and-forget; the phone runs
    /// the Graph call and re-pushes the snapshot.
    func sendSetEmailFlag(id: String, flagged: Bool) {
        send([
            WireKey.actionKind: ActionKind.setEmailFlagged.rawValue,
            WireKey.id: id,
            WireKey.flagged: flagged
        ])
    }

    /// Outcome of a watch-initiated refresh request, used by the glance
    /// to decide whether to surface a "Phone unreachable" hint after
    /// the pull-to-refresh spinner finishes.
    enum RefreshResult {
        /// A fresh snapshot landed before the wait window expired.
        case refreshed
        /// The phone isn't reachable right now — there's no way to ask
        /// it to refresh until the link comes back.
        case phoneUnreachable
        /// The request was sent but no fresh snapshot arrived inside
        /// the wait window. Treated like unreachable from the user's
        /// perspective: the data on screen hasn't moved.
        case timedOut
    }

    /// Ask the phone for a fresh refresh. Returns when a new snapshot
    /// lands (detected by the `updatedAt` advancing), when the wait
    /// window expires, or immediately when the phone isn't reachable.
    /// Drives the glance's `.refreshable` modifier — its spinner stays
    /// up until this returns, so the user sees it stop exactly when
    /// fresh data arrives.
    @MainActor
    func sendRefreshRequest() async -> RefreshResult {
        guard WCSession.isSupported() else { return .phoneUnreachable }
        let session = WCSession.default
        // On glance open this request often races WCSession activation:
        // the link comes up a beat after the view appears, so a bare
        // reachability check here false-flags a connection that's about
        // to succeed. Give it a short grace window to finish activating
        // and become reachable before declaring the phone unreachable.
        let reachableDeadline = Date().addingTimeInterval(3)
        while Date() < reachableDeadline {
            if session.activationState == .activated, session.isReachable { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else {
            return .phoneUnreachable
        }
        let before = snapshot?.updatedAt
        session.sendMessage(
            [WireKey.actionKind: ActionKind.refresh.rawValue],
            replyHandler: nil,
            errorHandler: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.logger.error("refresh sendMessage failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        )
        let start = Date()
        while Date().timeIntervalSince(start) < 10 {
            if let updatedAt = snapshot?.updatedAt, updatedAt != before {
                return .refreshed
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return .timedOut
    }

    /// Ask the phone for a full email body. Returns the text, or nil when the
    /// phone isn't reachable or the fetch fails — the reader then falls back to
    /// the snapshot preview it already has.
    @MainActor
    func requestEmailBody(id: String) async -> String? {
        await requestBody(kind: .fetchEmailBody, id: id)
    }

    /// Ask the phone for a chat's recent transcript. Same fallback semantics.
    @MainActor
    func requestChatBody(id: String) async -> String? {
        await requestBody(kind: .fetchChatBody, id: id)
    }

    /// Ask the phone for the recent inbox (read + unread) to browse deeper than
    /// the pushed unread front. Returns nil when the phone isn't reachable or
    /// the fetch fails, so the list keeps showing what it already has.
    @MainActor
    func requestMoreEmails() async -> [SnapshotEmail]? {
        guard let data = await requestItems(kind: .fetchMoreEmails) else { return nil }
        return try? JSONDecoder().decode([SnapshotEmail].self, from: data)
    }

    /// Ask the phone for recent chats (read + unread). Same semantics.
    @MainActor
    func requestMoreChats() async -> [SnapshotChat]? {
        guard let data = await requestItems(kind: .fetchMoreChats) else { return nil }
        return try? JSONDecoder().decode([SnapshotChat].self, from: data)
    }

    @MainActor
    private func requestItems(kind: ActionKind) async -> Data? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if session.activationState == .activated, session.isReachable { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [WireKey.actionKind: kind.rawValue],
                replyHandler: { reply in
                    continuation.resume(returning: reply[WireKey.items] as? Data)
                },
                errorHandler: { _ in
                    continuation.resume(returning: nil)
                }
            )
        }
    }

    /// Send an email reply-all from the wrist and wait for the phone's ack.
    /// Returns true when the phone confirms the send, false when it fails or
    /// the phone isn't reachable — a reply is a real send, so we never queue it
    /// silently; the caller tells the user to open the iPhone instead.
    @MainActor
    func sendReplyEmail(id: String, text: String) async -> Bool {
        await sendReply(kind: .replyEmail, id: id, text: text)
    }

    /// Send a Teams chat reply from the wrist. Same ack semantics.
    @MainActor
    func sendReplyChat(id: String, text: String) async -> Bool {
        await sendReply(kind: .replyChat, id: id, text: text)
    }

    @MainActor
    private func sendReply(kind: ActionKind, id: String, text: String) async -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        // Same activation/reachability grace window the body fetch uses.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if session.activationState == .activated, session.isReachable { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else { return false }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [WireKey.actionKind: kind.rawValue, WireKey.id: id, WireKey.text: text],
                replyHandler: { reply in
                    continuation.resume(returning: reply[WireKey.ok] as? Bool ?? false)
                },
                errorHandler: { _ in
                    continuation.resume(returning: false)
                }
            )
        }
    }

    @MainActor
    private func requestBody(kind: ActionKind, id: String) async -> String? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        // Same activation/reachability grace window the refresh request uses:
        // the link often comes up a beat after a view appears.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if session.activationState == .activated, session.isReachable { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [WireKey.actionKind: kind.rawValue, WireKey.id: id],
                replyHandler: { reply in
                    continuation.resume(returning: reply[WireKey.body] as? String)
                },
                errorHandler: { _ in
                    continuation.resume(returning: nil)
                }
            )
        }
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(payload)
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.logger.error("sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription, privacy: .public)")
                    session.transferUserInfo(payload)
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    @MainActor
    fileprivate func applyIncoming(_ context: [String: Any]) {
        guard let data = context[WireKey.snapshot] as? Data else {
            logger.error("applyIncoming: missing snapshot payload")
            return
        }
        guard let decoded = try? JSONDecoder().decode(CheckInSnapshot.self, from: data) else {
            logger.error("applyIncoming: failed to decode snapshot")
            return
        }
        snapshot = decoded
        decoded.saveToAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
        WidgetCenter.shared.reloadAllTimelines()
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

extension WatchSessionReceiver: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in
                self.logger.error("activation error: \(message, privacy: .public)")
                self.isActivated = (activationState == .activated)
            }
            return
        }
        let pending = session.receivedApplicationContext
        Task { @MainActor in
            self.isActivated = (activationState == .activated)
            // Adopt the receivedApplicationContext that was waiting at
            // activation, so a watch launched after the phone has
            // already pushed sees the latest state immediately.
            if !pending.isEmpty {
                self.applyIncoming(pending)
            }
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyIncoming(applicationContext)
        }
    }
}
