// GraphPresence.swift
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation

/// Presence and Out-of-Office operations, shared by the app's `GraphClient`
/// and the widget extension. Each rides `GraphCore`'s HTTP primitives, so
/// there is one implementation of every presence/OOO call regardless of which
/// process runs it.
public extension GraphCore {
    /// Current Microsoft 365 presence (collapsed to our smaller enum) plus the
    /// short custom status message that shows under the user's name in Teams.
    /// Empty string when no message is set. Presence.ReadWrite required.
    func fetchPresence() async throws -> (presence: Presence, statusMessage: String) {
        let data: PresenceResponse = try await get("/me/presence")
        let message = data.statusMessage?.message?.content ?? ""
        return (Presence(graphAvailability: data.availability), message)
    }

    /// Pin the user's preferred presence, overriding Teams' own auto-detection
    /// (which would otherwise flip the user to "In a meeting" or "Available"
    /// based on the calendar). Set for one day (`P1D`). It shows only while a
    /// presence session exists (see `setSessionPresence`); with no session the
    /// user shows Offline, not this value. Cleared by `clearUserPreferredPresence`.
    func setUserPreferredPresence(_ presence: Presence) async throws {
        guard let availability = presence.graphAvailability,
              let activity = presence.graphActivity else { return }
        try await post(
            "/me/presence/setUserPreferredPresence",
            body: SetPresenceBody(
                availability: availability,
                activity: activity,
                expirationDuration: "P1D"
            )
        )
    }

    /// Drop the user-preferred presence so Teams resumes auto-detection.
    /// POSTs an empty body.
    func clearUserPreferredPresence() async throws {
        try await emptyPost("/me/presence/clearUserPreferredPresence")
    }

    /// Set (or clear) the user's Teams status message — the short text shown
    /// under the user's name in Teams, independent of presence. Passing an
    /// empty string clears it.
    func setStatusMessage(_ content: String) async throws {
        try await post(
            "/me/presence/setStatusMessage",
            body: SetStatusMessageBody(content: content)
        )
    }

    /// Register CheckIn as an active presence-session source so the user's
    /// preferred presence keeps applying even when no other Microsoft client
    /// (Teams) holds a session. Max expiration is `PT1H`; callers re-up on
    /// every refresh. `.offline` is not a valid combination for this endpoint,
    /// so an Offline presence is skipped.
    func setSessionPresence(sessionId: String, presence: Presence) async throws {
        guard let availability = presence.graphAvailability,
              let activity = presence.graphActivity,
              availability != "Offline" else { return }
        try await post(
            "/me/presence/setPresence",
            body: SetSessionPresenceBody(
                sessionId: sessionId,
                availability: availability,
                activity: activity,
                expirationDuration: "PT1H"
            )
        )
    }

    /// Whether Outlook automatic replies are on. Any non-`disabled` state
    /// (`alwaysEnabled`, `scheduled`) reads as "out of office is on" — CheckIn
    /// doesn't model scheduled-with-dates; the user manages dates in Outlook
    /// web and CheckIn shows on/off.
    func fetchAutomaticRepliesEnabled() async throws -> Bool {
        let current = try await fetchAutomaticReplies()
        return current.status != "disabled"
    }

    /// Turn the user's auto-reply on. If their existing internal/external
    /// message is empty, fills in `defaultMessage` so people don't get blank
    /// auto-replies. Otherwise preserves whatever they already had (likely set
    /// via Outlook web).
    func enableAutomaticReplies(defaultMessage: String) async throws {
        let current = try await fetchAutomaticReplies()
        let internalMsg = current.internalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultMessage
        let externalMsg = current.externalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultMessage
        let body = MailboxSettingsFull(
            automaticRepliesSetting: AutomaticRepliesFull(
                status: "alwaysEnabled",
                externalAudience: current.externalAudience ?? "all",
                internalReplyMessage: internalMsg,
                externalReplyMessage: externalMsg
            )
        )
        try await patch("/me/mailboxSettings", body: body)
    }

    /// Turn the user's auto-reply off. PATCHes status only so existing messages
    /// are preserved for next time.
    func disableAutomaticReplies() async throws {
        let body = MailboxSettingsStatusOnly(
            automaticRepliesSetting: AutomaticRepliesStatusOnly(status: "disabled")
        )
        try await patch("/me/mailboxSettings", body: body)
    }

    /// Read the raw auto-reply settings. Internal to the module: callers use
    /// `fetchAutomaticRepliesEnabled` for the indicator; `enableAutomaticReplies`
    /// uses this to preserve any existing reply text when toggling on.
    internal func fetchAutomaticReplies() async throws -> AutomaticRepliesResponse {
        try await get("/me/mailboxSettings/automaticRepliesSetting")
    }
}

// MARK: - Wire-format types (module-internal)

struct PresenceResponse: Decodable {
    let availability: String
    let statusMessage: StatusMessageEnvelope?
}

struct StatusMessageEnvelope: Decodable {
    let message: StatusMessageContent?
}

struct StatusMessageContent: Decodable {
    let content: String?
}

struct SetPresenceBody: Encodable {
    let availability: String
    let activity: String
    let expirationDuration: String  // ISO 8601 duration, e.g. "P1D"
}

/// Body for `/me/presence/setPresence` — the app-session endpoint that
/// registers CheckIn as an active presence source. Distinct from the
/// user-preferred body above: this one requires a `sessionId`.
struct SetSessionPresenceBody: Encodable {
    let sessionId: String
    let availability: String
    let activity: String
    let expirationDuration: String  // ISO 8601, max "PT1H"
}

struct SetStatusMessageBody: Encodable {
    let statusMessage: StatusMessagePayload

    init(content: String) {
        statusMessage = StatusMessagePayload(
            message: StatusMessagePayloadContent(content: content, contentType: "text")
        )
    }
}

struct StatusMessagePayload: Encodable {
    let message: StatusMessagePayloadContent
}

struct StatusMessagePayloadContent: Encodable {
    let content: String
    let contentType: String
}

/// Subset of `/me/mailboxSettings/automaticRepliesSetting` CheckIn cares about.
/// `status` drives the OOO indicator; the messages are kept so a user's
/// existing auto-reply text is preserved when toggling rather than overwritten.
struct AutomaticRepliesResponse: Decodable {
    let status: String  // disabled | alwaysEnabled | scheduled
    let externalAudience: String?
    let internalReplyMessage: String?
    let externalReplyMessage: String?
}

struct MailboxSettingsFull: Encodable {
    let automaticRepliesSetting: AutomaticRepliesFull
}

struct AutomaticRepliesFull: Encodable {
    let status: String
    let externalAudience: String
    let internalReplyMessage: String
    let externalReplyMessage: String
}

struct MailboxSettingsStatusOnly: Encodable {
    let automaticRepliesSetting: AutomaticRepliesStatusOnly
}

struct AutomaticRepliesStatusOnly: Encodable {
    let status: String
}
