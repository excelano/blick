// Command.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// A user-resolved action against the inbox. Exactly the operations the
/// GUI exposes — no more. Voice and touch both produce these; the touch
/// surface emits them directly from gestures, the voice surface emits
/// them through `Interpreter`. As new touch gestures land, new cases
/// land here; voice never gets ahead of the GUI.
enum Command: Equatable {
    case refresh
}

/// What the executor returns from running a command. `spokenResponse` is
/// the canonical phrasing — single string per outcome, no persona pool.
/// Empty string means silent (e.g., a deep-link that's its own feedback
/// via the app switch).
struct CommandResult: Equatable {
    let spokenResponse: String
}

/// Runs commands. Voice and touch both route here so a single execution
/// path covers both inputs. Currently delegates to `InboxActions` for
/// mutations and to URL openers for deep links; the shape will grow as
/// more commands land.
@MainActor
final class CommandExecutor {
    private let inboxActions: InboxActions

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "executor")

    init(inboxActions: InboxActions) {
        self.inboxActions = inboxActions
    }

    func execute(_ command: Command) async -> CommandResult {
        #if DEBUG
        print("[command] execute \(command)")
        #endif
        switch command {
        case .refresh:
            await inboxActions.refresh()
            return CommandResult(spokenResponse: "Refreshed.")
        }
    }
}
