// UnreadFromSenderIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Count unread emails from a particular sender (by name or address)
/// from Siri, Shortcuts, or Spotlight. Refreshes the full unread set
/// first so the match covers the whole mailbox, not just the visible
/// window. Runs headless.
struct UnreadFromSenderIntent: AppIntent {
    static var title: LocalizedStringResource = "Count Unread from Sender"
    static var description = IntentDescription(
        "Count your unread emails from a particular sender."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Sender")
    var sender: String

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    init() {}

    init(sender: String) {
        self.sender = sender
    }

    static var parameterSummary: some ParameterSummary {
        Summary("How many unread emails from \(\.$sender)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.refresh(fetchAllEmails: true)

        let n = inbox.unreadCount(fromSenderMatching: sender)
        let dialog: IntentDialog = switch n {
        case 0: "You have no unread emails from \(sender)."
        case 1: "You have 1 unread email from \(sender)."
        default: "You have \(n) unread emails from \(sender)."
        }
        return .result(value: n, dialog: dialog)
    }
}
