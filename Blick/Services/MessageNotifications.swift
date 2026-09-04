// MessageNotifications.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UserNotifications
import os

/// Posts one local notification per genuinely new message, immediately.
/// `Inbox` decides what is new (via `NewMessageTracker`) and who qualifies
/// (the per-channel scope and the starred set); this only builds and
/// delivers the content.
///
/// Identifiers carry the `blick.message.` prefix, a sibling of the meeting
/// reminders' `blick.meeting.`, so each service can find its own requests
/// and neither touches the other's. Mail and chat get separate thread
/// identifiers so Notification Center stacks them as two groups.
@MainActor
final class MessageNotifications {
    private let identifierPrefix = "blick.message."
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "notifications")

    func post(emails: [Email], chats: [ChatMessage]) async {
        guard await NotificationAuthorization.isGranted() else { return }
        let center = UNUserNotificationCenter.current()
        for email in emails {
            let content = UNMutableNotificationContent()
            content.title = email.from
            content.subtitle = email.subject
            content.body = email.preview
            content.sound = .default
            content.threadIdentifier = "blick.mail"
            content.userInfo["emailId"] = email.id
            await add(content, id: "mail." + email.id, to: center)
        }
        for chat in chats {
            guard let key = Self.key(for: chat) else { continue }
            let content = UNMutableNotificationContent()
            content.title = chat.from
            if !chat.topic.isEmpty { content.subtitle = chat.topic }
            content.body = chat.preview
            content.sound = .default
            content.threadIdentifier = "blick.chat"
            if let chatId = chat.chatId { content.userInfo["chatId"] = chatId }
            await add(content, id: "chat." + key, to: center)
        }
    }

    /// A chat's identity for dedupe. `ChatMessage.id` is a per-instance
    /// UUID, so the thread plus the last message's timestamp stands in: a
    /// new message in the same thread has a new timestamp. Chats without a
    /// thread id cannot be keyed and are never nudged.
    static func key(for chat: ChatMessage) -> String? {
        guard let chatId = chat.chatId else { return nil }
        return "\(chatId)|\(Int(chat.sent.timeIntervalSince1970))"
    }

    private func add(_ content: UNMutableNotificationContent, id: String, to center: UNUserNotificationCenter) async {
        let request = UNNotificationRequest(identifier: identifierPrefix + id, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logger.error("post failed for \(content.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
