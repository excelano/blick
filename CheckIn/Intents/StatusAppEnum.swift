// StatusAppEnum.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// The Microsoft 365 presence states a user can set from a shortcut. A narrowed
/// subset of `Presence` — only the values that make sense as an
/// explicit, user-chosen status — plus `resetToAuto`, which clears the
/// preferred presence and lets Microsoft 365 auto-detect again.
enum StatusAppEnum: String, AppEnum {
    case available
    case busy
    case doNotDisturb
    case away
    case resetToAuto

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Status"
    }

    static var caseDisplayRepresentations: [StatusAppEnum: DisplayRepresentation] {
        [
            .available: "Available",
            .busy: "Busy",
            .doNotDisturb: "Do Not Disturb",
            .away: "Away",
            .resetToAuto: "Reset to Automatic",
        ]
    }

    /// Maps to the app's presence model. `resetToAuto` becomes `.unknown`,
    /// which `Inbox.setPresence(_:)` treats as "clear my preferred
    /// presence and re-fetch the auto-detected state".
    var asPresence: Presence {
        switch self {
        case .available: return .available
        case .busy: return .busy
        case .doNotDisturb: return .doNotDisturb
        case .away: return .away
        case .resetToAuto: return .unknown
        }
    }
}
