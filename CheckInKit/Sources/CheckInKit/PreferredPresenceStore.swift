// PreferredPresenceStore.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Records the preferred presence CheckIn last pinned via Graph's
/// `setUserPreferredPresence`, together with when that pin lapses. Graph
/// exposes no read for the preferred override or its expiry, so this is the
/// only way to know whether *our* pin is still in effect — which the Offline
/// heartbeat-pause depends on, and which lets the surfaces reason about a pin
/// that's ours versus one Teams auto-detected.
///
/// Persisted in the shared App Group so the app process (foreground and the
/// background-refresh task) and the widget extension agree on the pin: a pin
/// set from a widget button must pause the app's heartbeat, and vice versa.
///
/// The expiry mirrors the `P1D` duration sent to Graph in
/// `setUserPreferredPresence`; the two must stay in step.
public struct PreferredPresenceStore: Sendable {
    /// The ISO 8601 expiration sent to Graph in `setUserPreferredPresence`.
    /// Single source of truth for the preferred-pin lifetime: `pinDuration`
    /// below is its `TimeInterval` form, and both live here so they can't
    /// drift across modules. Change one, change the other.
    public static let pinExpirationISO8601 = "P1D"

    /// How long a preferred-presence pin lasts, as a `TimeInterval`. Must
    /// equal `pinExpirationISO8601` (`P1D` = 24h); the store uses it to know
    /// when our pin has lapsed, which must match when Graph drops it.
    public static let pinDuration: TimeInterval = 24 * 60 * 60

    private let suite: String

    public init(suite: String = CheckInSnapshot.appGroupIdentifier) {
        self.suite = suite
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    private static let presenceKey = "preferredPresence"
    private static let expiryKey = "preferredPresenceExpiry"

    /// The presence we pinned and when it lapses, or `nil` when nothing is
    /// pinned or the pin has already expired. Reading an expired pin clears it,
    /// so the caller can treat `nil` as "back to automatic."
    public func current(now: Date = Date()) -> (presence: Presence, expiry: Date)? {
        guard let defaults,
              let raw = defaults.string(forKey: Self.presenceKey),
              let presence = Presence(rawValue: raw),
              let expiry = defaults.object(forKey: Self.expiryKey) as? Date else {
            return nil
        }
        guard expiry > now else {
            clear()
            return nil
        }
        return (presence, expiry)
    }

    /// Record a freshly-set pin, expiring `pinDuration` after `now`.
    public func pin(_ presence: Presence, now: Date = Date()) {
        guard let defaults else { return }
        defaults.set(presence.rawValue, forKey: Self.presenceKey)
        defaults.set(now.addingTimeInterval(Self.pinDuration), forKey: Self.expiryKey)
    }

    /// Drop the pin record — reset-to-auto, or a confirmed clear.
    public func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Self.presenceKey)
        defaults.removeObject(forKey: Self.expiryKey)
    }
}
