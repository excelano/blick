// GraphTypes.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Wire-format types for Microsoft Graph requests and responses. These
// are intentionally minimal — only the fields CheckIn reads or sends.
// `internal` access so GraphClient can reference them from a sibling
// file; nothing outside Services/ should need to.

import Foundation

struct UserResponse: Decodable {
    let id: String
    let mail: String?
    let userPrincipalName: String?
}

struct CalendarEventResponse: Decodable {
    let id: String
    let subject: String
    let organizer: OrganizerResponse
    let start: DateTimeResponse
    let end: DateTimeResponse
    let onlineMeeting: OnlineMeetingResponse?
    let responseStatus: EventResponseStatus?
    let isCancelled: Bool?
    /// Universal meeting identifier — Graph's hex-encoded form of the
    /// underlying MAPI `PidLidGlobalObjectId`. Same value on the
    /// corresponding invitation eventMessage, so it's the deterministic
    /// join key for email↔meeting matching.
    let iCalUId: String?
}

struct EventResponseStatus: Decodable {
    let response: String
}

struct OnlineMeetingResponse: Decodable {
    let joinUrl: String?
}

struct OrganizerResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

struct DateTimeResponse: Decodable {
    let dateTime: String
    let timeZone: String
}

struct EmailAddressResponse: Decodable {
    let name: String
    let address: String?
}

/// Minimal shape for `fetchInviteICalUId`. The MAPI named property
/// `PidLidGlobalObjectId` is exposed via `singleValueExtendedProperties`
/// filtered to the meeting namespace ({6ED8DA90-…}/0x3). Its base64
/// value, hex-decoded, equals the iCalUId of the corresponding event —
/// the deterministic join key from eventMessage to event.
struct MessageSingleValueExtPropResponse: Decodable {
    let singleValueExtendedProperties: [SingleValueExtPropResponse]?
}

struct SingleValueExtPropResponse: Decodable {
    let id: String
    let value: String?
}

struct EmailResponse: Decodable {
    let id: String
    let subject: String
    /// Optional because search spans all folders, and a Draft carries no
    /// sender until it's sent — a non-optional `from` would fail the whole
    /// list decode on one draft in the results.
    let from: EmailAddressEnvelope?
    let toRecipients: [EmailAddressEnvelope]?
    let ccRecipients: [EmailAddressEnvelope]?
    let bodyPreview: String
    let receivedDateTime: String
    let isRead: Bool?
    let flag: FlagResponse?
    let inferenceClassification: String?
    let meetingMessageType: String?
    /// Meeting times pulled via `microsoft.graph.eventMessage/startDateTime`
    /// (and `endDateTime`) in the list query's `$select`. Present only on
    /// invitation/cancellation/response messages; nil otherwise.
    let startDateTime: DateTimeResponse?
    let endDateTime: DateTimeResponse?
    let internetMessageHeaders: [InternetMessageHeader]?
}

struct InternetMessageHeader: Decodable {
    let name: String
    let value: String
}

struct FlagResponse: Decodable {
    let flagStatus: String?
}

struct EmailAddressEnvelope: Decodable {
    let emailAddress: EmailAddressResponse
}

struct BodyContentResponse: Decodable {
    let contentType: String
    let content: String
}

/// Used when we only need the message id from a list query (e.g.,
/// fetching today's read messages so we can flip them back to unread).
struct EmailIdResponse: Decodable {
    let id: String
}

/// Used by `fetchEmailContent` to pull just the message body. Combined with
/// the `Prefer: outlook.body-content-type="html"` request header so Graph
/// returns the sender's HTML in `body.content` for the rich render. The
/// attachment metadata is a separate, best-effort call so a failure there
/// never blanks the body.
struct EmailBodyResponse: Decodable {
    let body: BodyContentResponse
}

/// One attachment's metadata as Graph reports it. `contentType`,
/// `contentId`, and `name` are absent on some attachment kinds
/// (itemAttachment, referenceAttachment), so all are optional. `isInline`
/// is Graph's own claim; Klartext re-decides truly-inline via the cid join
/// against the body HTML.
struct AttachmentMetaResponse: Decodable {
    let id: String
    let name: String?
    let contentType: String?
    let size: Int?
    let isInline: Bool?
    let contentId: String?
}

/// The base64 bytes of a single attachment, fetched on demand for inline
/// images so the HTML web view can paint `cid:` resources on device.
struct AttachmentBytesResponse: Decodable {
    let contentBytes: String?
}

/// POST body for `/me/messages/{id}/replyAll` — Graph wraps the user's
/// short message in `comment` and stitches it onto the original
/// conversation with proper `In-Reply-To` / `References` threading.
struct ReplyCommentBody: Encodable {
    let comment: String
}

/// A recipient on an outgoing message. Graph accepts an `emailAddress`
/// carrying only `address`; the display `name` is optional and we omit it
/// (the server resolves the name from the directory / the address itself).
/// The Decodable read side is `EmailAddressEnvelope`; this is its write twin.
struct OutgoingRecipientBody: Encodable {
    let emailAddress: OutgoingAddressBody
}

struct OutgoingAddressBody: Encodable {
    let address: String
}

/// Body content envelope for an outgoing message. `contentType` is `Text`
/// for compose (plain text, matches the reply surface).
struct OutgoingBodyContent: Encodable {
    let contentType: String
    let content: String
}

/// The message half of a `/me/sendMail` request.
struct OutgoingMessageBody: Encodable {
    let subject: String
    let body: OutgoingBodyContent
    let toRecipients: [OutgoingRecipientBody]
    let ccRecipients: [OutgoingRecipientBody]
    let bccRecipients: [OutgoingRecipientBody]
}

/// POST body for `/me/sendMail`. `saveToSentItems` keeps a copy in Sent,
/// which is the expected behavior for a mail client.
struct SendMailBody: Encodable {
    let message: OutgoingMessageBody
    let saveToSentItems: Bool
}

/// POST body for `/me/messages/{id}/forward`. Graph builds the "Fwd:"
/// subject and quotes the original body server-side, so we only supply the
/// added note (`comment`) and the recipients — no need to load the body.
struct ForwardBody: Encodable {
    let comment: String
    let toRecipients: [OutgoingRecipientBody]
}

/// POST body for `/me/chats/{chatId}/messages`. Graph expects `body`
/// as a content envelope identical in shape to the lastMessagePreview
/// body we read elsewhere.
struct ChatMessageSendBody: Encodable {
    let body: ChatMessageSendContent
}

struct ChatMessageSendContent: Encodable {
    let contentType: String
    let content: String
}

/// POST body for `/chats` — creates a new Teams chat and names its members.
/// `chatType` is "oneOnOne" for exactly two members (the signed-in user plus
/// one other) or "group" for more; a 1:1 create is idempotent, returning the
/// existing thread rather than a duplicate.
struct CreateChatBody: Encodable {
    let chatType: String
    let members: [CreateChatMemberBody]
}

/// One member of a new chat. Graph binds a member to an Azure AD user by an
/// odata reference; the `@`-keyed JSON names (`@odata.type`,
/// `user@odata.bind`) aren't legal Swift identifiers, so `CodingKeys` maps
/// them. `userRef` is the full `/users('{upn-or-id}')` URL — we bind the
/// signed-in user by their `/me` id and each recipient by email-as-UPN
/// (the cheap path: an alias or external address fails at create time).
struct CreateChatMemberBody: Encodable {
    let odataType = "#microsoft.graph.aadUserConversationMember"
    let roles = ["owner"]
    let userRef: String

    enum CodingKeys: String, CodingKey {
        case odataType = "@odata.type"
        case roles
        case userRef = "user@odata.bind"
    }
}

/// POST body for `/chats/{id}/markChatReadForUser`. The user identity
/// requires both id and tenantId — tenantId comes from MSAL's
/// homeAccountId, id from /me.
struct MarkChatReadBody: Encodable {
    let user: TeamworkUserIdentityBody
}

/// POST body for `/chats/{id}/markChatUnreadForUser`. Per Graph docs,
/// when `lastMessageReadDateTime` is omitted the API defaults to
/// "mark the last message unread" — which is exactly what we want
/// here, so we just don't send the field. Avoids the trap of Graph
/// rejecting out-of-range timestamps (1970 etc.) for that parameter.
struct MarkChatUnreadBody: Encodable {
    let user: TeamworkUserIdentityBody
}

struct TeamworkUserIdentityBody: Encodable {
    let id: String
    let tenantId: String
}

struct ChatResponse: Decodable {
    let id: String
    let topic: String?
    let webUrl: String?
    let lastMessagePreview: ChatPreviewResponse?
    let members: [ChatMemberResponse]?
    /// Per-user state for this chat. `lastMessageReadDateTime` is the
    /// signal we use to decide whether a chat has unread activity:
    /// unread iff `lastMessagePreview.createdDateTime` is newer.
    /// `isHidden` reflects the user hiding the chat in Teams; we honor
    /// that and skip hidden chats entirely.
    let viewpoint: ChatViewpointResponse?
}

struct ChatViewpointResponse: Decodable {
    let isHidden: Bool?
    /// ISO8601. `"0001-01-01T00:00:00Z"` for chats the user has never
    /// opened — the comparison still works because that date is older
    /// than any real `createdDateTime`.
    let lastMessageReadDateTime: String?
}

struct ChatMemberResponse: Decodable {
    let userId: String?
    let displayName: String?
}

struct ChatPreviewResponse: Decodable {
    let body: BodyContentResponse
    let from: ChatFromResponse?
    let createdDateTime: String
    let messageType: String
}

/// A full message from `/chats/{chatId}/messages`. Same envelope as
/// `ChatPreviewResponse` (the chat's lastMessagePreview) plus the message
/// `id`, used to render the recent-thread transcript in the preview sheet.
struct ChatMessageResponse: Decodable {
    let id: String
    let body: BodyContentResponse
    let from: ChatFromResponse?
    let createdDateTime: String
    let messageType: String
    /// File, card, and reference attachments carried on the message. The
    /// transcript shows the body stripped to plain text, so a non-empty
    /// list means there is content we aren't rendering. We decode only
    /// `contentType` and `name`, enough to guess whether an item is an
    /// image (Teams tags shared files `reference`, so the filename
    /// extension is the workable signal). Pasted inline images are not
    /// here — they live in the body HTML as `<img>` and are detected there.
    let attachments: [ChatAttachmentResponse]?
}

/// A chat-message attachment, decoded for the unshown-content indicator.
struct ChatAttachmentResponse: Decodable {
    let contentType: String?
    let name: String?
}

struct ChatFromResponse: Decodable {
    let user: ChatUserResponse?
}

struct ChatUserResponse: Decodable {
    let id: String
    let displayName: String
}

struct MarkReadBody: Encodable {
    let isRead: Bool
}

struct FlagBody: Encodable {
    let flag: FlagStatusBody
}

struct FlagStatusBody: Encodable {
    let flagStatus: String
}

struct RsvpBody: Encodable {
    let sendResponse: Bool
}

struct BatchRequest<B: Encodable>: Encodable {
    let id: String
    let method: String
    let url: String
    let headers: [String: String]
    let body: B
}

struct BatchEnvelope<B: Encodable>: Encodable {
    let requests: [BatchRequest<B>]
}

struct BatchResponse: Decodable {
    let responses: [BatchResponseItem]
}

struct BatchResponseItem: Decodable {
    let id: String
    let status: Int
}
