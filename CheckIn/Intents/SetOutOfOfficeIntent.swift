// SetOutOfOfficeIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Turn Outlook automatic replies (Out of Office) on or off from Siri,
/// Shortcuts, or Spotlight. Uses the app's default Out of Office message
/// when enabling; an existing message set elsewhere is preserved.
struct SetOutOfOfficeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Out of Office"
    static var description = IntentDescription(
        "Turn your Outlook automatic replies (Out of Office) on or off."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Turn On", default: true)
    var turnOn: Bool

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    init() {}

    init(turnOn: Bool) {
        self.turnOn = turnOn
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set Out of Office \(\.$turnOn)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.setOutOfOffice(turnOn)
        let dialog: IntentDialog = turnOn
            ? "Out of Office is now on."
            : "Out of Office is now off."
        return .result(dialog: dialog)
    }
}
