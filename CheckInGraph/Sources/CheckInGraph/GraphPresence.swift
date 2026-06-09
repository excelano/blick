// GraphPresence.swift
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation

/// The outcome of `applyPreferredPresence`: what Graph reports after the write
/// (the source of truth for the display) and whether Microsoft honored the
/// requested state. `honored` is `false` when the effective presence doesn't
/// match the request, and callers must not report success then.
public struct PresenceApplyResult {
    public let effective: Presence
    public let statusMessage: String
    public let honored: Bool
}

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
                expirationDuration: PreferredPresenceStore.pinExpirationISO8601
            )
        )
    }

    /// Drop the user-preferred presence so Teams resumes auto-detection.
    /// POSTs an empty body.
    func clearUserPreferredPresence() async throws {
        try await emptyPost("/me/presence/clearUserPreferredPresence")
    }

    /// Tear down CheckIn's presence session immediately, rather than waiting
    /// for it to lapse. The counterpart to `setSessionPresence`. Used when the
    /// user pins Offline: with no session of ours reporting Available, the user
    /// actually shows Offline instead of lingering visible until the session
    /// would otherwise expire. Identifies the session by the same `sessionId`
    /// we set it with.
    func clearSessionPresence(sessionId: String) async throws {
        try await post(
            "/me/presence/clearPresence",
            body: ClearPresenceBody(sessionId: sessionId)
        )
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
    /// (Teams) holds a session. `PT1H` expiration, renewed on every refresh
    /// (≈30 min), so it never lapses while CheckIn is in use. `.offline` is not
    /// a valid combination for this endpoint, so an Offline presence is skipped
    /// (the Offline case tears the session down via `clearSessionPresence`).
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

    /// Apply a preferred presence end to end, then read back what Graph
    /// actually reports so the caller can show the truth rather than the
    /// request. One implementation for every process (app, Siri, widget).
    ///
    /// - `.unknown` clears the pin (reset to auto) and keeps the session alive
    ///   at Available, so the user stays visible rather than dropping Offline.
    /// - `.offline` tears our session down and pins Offline, so the user shows
    ///   Offline instead of our heartbeat's Available; the caller pauses the
    ///   heartbeat while the pin holds.
    /// - Any other state re-ups the session at Available (so Graph honors the
    ///   override even when no Teams client runs) and pins that state.
    ///
    /// `honored` reflects a read-back comparison, not just an HTTP 200:
    /// presence is eventually consistent, so on a first mismatch this waits
    /// briefly and reads once more before concluding the request didn't take.
    /// A tenant policy, Conditional Access, or another client can override us,
    /// and the caller must not report success when `honored` is `false`.
    func applyPreferredPresence(
        _ presence: Presence,
        sessionId: String,
        store: PreferredPresenceStore,
        now: Date = Date()
    ) async throws -> PresenceApplyResult {
        switch presence {
        case .offline:
            // Best-effort teardown; a pin over no session of ours shows Offline.
            do { try await clearSessionPresence(sessionId: sessionId) }
            catch { /* best-effort: the session lapses on its own otherwise */ }
            try await setUserPreferredPresence(.offline)
            // Pin eagerly so a concurrent heartbeat stays paused during the
            // read-back below; cleared again if Graph didn't honor it.
            store.pin(.offline, now: now)
        case .unknown:
            await heartbeat(sessionId: sessionId)
            try await clearUserPreferredPresence()
            store.clear()
        default:
            await heartbeat(sessionId: sessionId)
            try await setUserPreferredPresence(presence)
        }

        var (effective, message) = try await fetchPresence()
        // Reset-to-auto has no specific target to confirm: the clear succeeding
        // is the success signal, and effective is whatever auto now resolves to.
        if presence == .unknown {
            return PresenceApplyResult(effective: effective, statusMessage: message, honored: true)
        }
        // Eventual consistency: give a first mismatch one short settle before
        // calling the request unhonored.
        if effective != presence {
            try? await Task.sleep(for: .milliseconds(800))
            (effective, message) = try await fetchPresence()
        }
        let honored = effective == presence
        // Record the pin only for a state Graph actually applied, so the
        // Offline heartbeat-pause can never get stuck suppressing the session
        // over a presence the server rejected.
        if honored {
            store.pin(presence, now: now)
        } else if presence == .offline {
            store.clear()
        }
        return PresenceApplyResult(effective: effective, statusMessage: message, honored: honored)
    }

    /// Re-up the presence session at Available, best-effort: a transient
    /// session failure must not abort the preferred-presence write. When it
    /// does fail and no other client holds a session, the override simply
    /// won't display, and the read-back honored check reports that truthfully.
    private func heartbeat(sessionId: String) async {
        do { try await setSessionPresence(sessionId: sessionId, presence: .available) }
        catch { /* best-effort; honored check catches the visible consequence */ }
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
    let expirationDuration: String  // ISO 8601; we send "PT1H", renewed every refresh
}

/// Body for `/me/presence/clearPresence` — tears down the app's session,
/// identified by the same `sessionId` used to set it.
struct ClearPresenceBody: Encodable {
    let sessionId: String
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
