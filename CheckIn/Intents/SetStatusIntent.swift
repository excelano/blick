// SetStatusIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Set the user's preferred Microsoft 365 presence (or reset to automatic) from
/// Siri, Shortcuts, or Spotlight. Runs headless — no app UI.
///
/// Known limitation, carried honestly from the app: a preferred presence
/// only takes visible effect when a Teams desktop session exists. Graph
/// returns success regardless, so this intent reports success the same
/// way the in-app picker does.
struct SetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Status"
    static var description = IntentDescription(
        "Set your Microsoft 365 status, or reset it to automatic."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Status")
    var status: StatusAppEnum

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    static var parameterSummary: some ParameterSummary {
        Summary("Set my status to \(\.$status)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Pre-flight a silent token refresh. On a headless launch this is
        // the only sign-in check we can make, and it primes the cache so
        // the operation's own GraphClient.authorize() silent call lands.
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.setPresence(status.asPresence)

        let dialog: IntentDialog
        if status == .resetToAuto {
            dialog = "Your CheckIn status is back to automatic."
        } else {
            dialog = "Your CheckIn status is now \(status.asPresence.displayName)."
        }
        return .result(dialog: dialog)
    }
}
