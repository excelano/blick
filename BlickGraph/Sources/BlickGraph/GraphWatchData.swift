// GraphWatchData.swift
// BlickGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickKit
import Foundation

/// The mail and chat reads and writes the watch makes for itself when the
/// phone is out of reach. Each mirrors the call the phone's `GraphClient` makes
/// for the same watch request, trimmed to the fields the watch shows.
public extension GraphCore {
    static let watchPreviewLimit = 140

    func fetchWatchEmails(unreadOnly: Bool, top: Int) async throws -> [SnapshotEmail] {
        var query = [
            "$orderby": "receivedDateTime desc",
            "$top": "\(top)",
            "$select": "id,subject,from,bodyPreview,receivedDateTime,isRead,flag"
        ]
        if unreadOnly { query["$filter"] = "isRead eq false" }
        let data: GraphList<WatchEmail> = try await get(
            "/me/mailFolders/inbox/messages",
            query: query,
            headers: unreadOnly ? ["ConsistencyLevel": "eventual"] : [:]
        )
        return data.value.map { email in
            SnapshotEmail(
                id: email.id,
                sender: email.from?.emailAddress.name ?? "",
                subject: email.subject,
                preview: String(plainText(fromHTML: email.bodyPreview).prefix(Self.watchPreviewLimit)),
                received: parseISO8601(email.receivedDateTime) ?? Date(),
                isFlagged: email.flag?.flagStatus == "flagged",
                isRead: email.isRead ?? false
            )
        }
    }

    func fetchWatchChats(unreadOnly: Bool, top: Int) async throws -> [BlickKit.SnapshotChat] {
        let data: GraphList<WatchChat> = try await get("/me/chats", query: [
            "$select": "id,lastMessagePreview,viewpoint",
            "$expand": "lastMessagePreview",
            "$top": "50"
        ])
        var chats: [BlickKit.SnapshotChat] = []
        for chat in data.value {
            guard let preview = chat.lastMessagePreview,
                  let sent = parseISO8601(preview.createdDateTime),
                  let sender = preview.from?.user else { continue }
            let lastRead = chat.viewpoint?.lastMessageReadDateTime.flatMap(parseISO8601)
            let displayable = isDisplayableChat(
                isHidden: chat.viewpoint?.isHidden,
                messageType: preview.messageType,
                hasSenderUser: true,
                sent: sent
            )
            let unread = isUnreadChat(
                isHidden: chat.viewpoint?.isHidden,
                messageType: preview.messageType,
                hasSenderUser: true,
                sent: sent,
                lastRead: lastRead
            )
            guard unreadOnly ? unread : displayable else { continue }
            chats.append(BlickKit.SnapshotChat(
                id: chat.id,
                sender: sender.displayName,
                preview: String(plainText(fromHTML: preview.body.content).prefix(Self.watchPreviewLimit)),
                sent: sent,
                isRead: !unread
            ))
        }
        return Array(chats.sorted { $0.sent > $1.sent }.prefix(top))
    }

    func setEmailRead(id: String, isRead: Bool) async throws {
        try await patch("/me/messages/\(id)", body: WatchReadBody(isRead: isRead))
    }

    func setEmailFlagged(id: String, flagged: Bool) async throws {
        try await patch("/me/messages/\(id)", body: WatchFlagBody(flag: .init(flagStatus: flagged ? "flagged" : "notFlagged")))
    }

    func setChatRead(id: String, isRead: Bool, identity: ChatIdentity) async throws {
        try await post(
            "/chats/\(id)/\(isRead ? "markChatReadForUser" : "markChatUnreadForUser")",
            body: WatchChatUserBody(user: .init(id: identity.userID, tenantId: identity.tenantID))
        )
    }

    func fetchEmailText(id: String) async throws -> String {
        let body: WatchEmailBody = try await get(
            "/me/messages/\(id)",
            query: ["$select": "body"],
            headers: ["Prefer": "outlook.body-content-type=\"text\""]
        )
        let text = body.body.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no message body)" : String(text.prefix(4000))
    }

    func fetchChatText(id: String, currentUserID: String, cap: Int = 20) async throws -> String {
        let page: GraphList<WatchChatMessage> = try await get("/chats/\(id)/messages", query: ["$top": "50"])
        let newestFirst = page.value
            .compactMap { message -> (WatchChatMessage, Date)? in
                parseISO8601(message.createdDateTime).map { (message, $0) }
            }
            .sorted { $0.1 > $1.1 }
        var lines: [String] = []
        for (message, _) in newestFirst {
            guard message.messageType == "message", let user = message.from?.user else { continue }
            let isMine = user.id == currentUserID
            let text = plainText(fromHTML: message.body.content)
            lines.append("\(isMine ? "You" : user.displayName): \(text.isEmpty ? "(no text)" : text)")
            if isMine || lines.count >= cap { break }
        }
        return lines.isEmpty ? "(no messages)" : lines.reversed().joined(separator: "\n\n")
    }

    func replyAll(emailID: String, text: String) async throws {
        let draft: WatchDraft = try await postDecoded("/me/messages/\(emailID)/createReplyAll", body: WatchEmptyBody())
        let isHTML = draft.body.contentType.caseInsensitiveCompare("html") == .orderedSame
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let prefix = isHTML ? escaped + "<br><br>" : text + "\n\n"
        try await patch(
            "/me/messages/\(draft.id)",
            body: WatchDraftPatch(body: .init(contentType: draft.body.contentType, content: prefix + draft.body.content))
        )
        try await post("/me/messages/\(draft.id)/send", body: WatchEmptyBody())
    }

    func sendChatReply(chatID: String, text: String) async throws {
        try await post(
            "/me/chats/\(chatID)/messages",
            body: WatchChatSend(body: .init(contentType: "text", content: text))
        )
    }
}

/// The signed-in user's directory id and home tenant, which Graph's per-user
/// chat read and unread endpoints require.
public struct ChatIdentity: Codable, Sendable {
    public let userID: String
    public let tenantID: String

    public init(userID: String, tenantID: String) {
        self.userID = userID
        self.tenantID = tenantID
    }
}

// MARK: - Lean shapes (module-internal)

struct WatchEmail: Decodable {
    let id: String
    let subject: String
    let from: WatchEnvelope?
    let bodyPreview: String
    let receivedDateTime: String
    let isRead: Bool?
    let flag: WatchFlag?
}

struct WatchEnvelope: Decodable {
    let emailAddress: WatchAddress
}

struct WatchAddress: Decodable {
    let name: String
}

struct WatchFlag: Decodable {
    let flagStatus: String?
}

struct WatchChat: Decodable {
    let id: String
    let lastMessagePreview: WatchChatPreview?
    let viewpoint: SnapshotViewpoint?
}

struct WatchChatPreview: Decodable {
    let body: WatchBody
    let from: WatchChatFrom?
    let createdDateTime: String
    let messageType: String
}

struct WatchChatFrom: Decodable {
    let user: WatchChatUser?
}

struct WatchChatUser: Decodable {
    let id: String
    let displayName: String
}

struct WatchBody: Decodable {
    let contentType: String
    let content: String
}

struct WatchEmailBody: Decodable {
    let body: WatchBody
}

struct WatchChatMessage: Decodable {
    let body: WatchBody
    let from: WatchChatFrom?
    let createdDateTime: String
    let messageType: String
}

struct WatchDraft: Decodable {
    let id: String
    let body: WatchBody
}

struct WatchEmptyBody: Encodable {}

struct WatchReadBody: Encodable {
    let isRead: Bool
}

struct WatchFlagBody: Encodable {
    struct Status: Encodable {
        let flagStatus: String
    }
    let flag: Status
}

struct WatchOutgoingBody: Encodable {
    let contentType: String
    let content: String
}

struct WatchDraftPatch: Encodable {
    let body: WatchOutgoingBody
}

struct WatchChatSend: Encodable {
    let body: WatchOutgoingBody
}

struct WatchChatUserBody: Encodable {
    struct User: Encodable {
        let id: String
        let tenantId: String
    }
    let user: User
}
