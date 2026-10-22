// WatchPresencePinWire.swift
// BlickKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// How a watch that set presence on its own tells the phone, so the phone's
/// pin record agrees and its heartbeat does not re-up Available over an
/// Offline the watch just pinned.
public enum WatchPresencePinWire {
    public static let reportKey = "watchPresencePin"
    public static let auto = "auto"

    public static func report(for presence: Presence) -> String {
        presence == .unknown ? auto : presence.rawValue
    }
}

extension PreferredPresenceStore {
    /// Mirror a pin the watch set, or clear the record when it reset to auto.
    public func record(watchReport report: String, now: Date = Date()) {
        if report == WatchPresencePinWire.auto {
            clear()
        } else if let presence = Presence(rawValue: report) {
            pin(presence, now: now)
        }
    }
}
