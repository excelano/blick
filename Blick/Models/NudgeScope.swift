// NudgeScope.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Who a channel's new-message nudge fires for. Stored per channel in
/// `AppStorage`; the default is starred senders only, which is the point
/// of the feature — a nudge for every message is noise, and noise is how
/// notification permission gets revoked altogether.
enum NudgeScope: String, CaseIterable, Identifiable {
    case off
    case starred
    case all

    static let `default` = NudgeScope.starred

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .starred: "Starred senders"
        case .all: "Everyone"
        }
    }

    /// Read a channel's setting, falling back to the default when unset.
    static func stored(forKey key: String) -> NudgeScope {
        UserDefaults.standard.string(forKey: key).flatMap(NudgeScope.init(rawValue:)) ?? .default
    }
}
