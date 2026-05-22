// DialogState.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Top-level app state. Sign-in gate plus an active substate that tracks
/// which sheet (if any) is presented.
enum DialogState: Equatable {
    case signedOut
    case active(ActiveSubstate)
}

enum ActiveSubstate: Equatable {
    case idle
    case helpDisplayed
    case settingsDisplayed
}
