// SetOutOfOfficeIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit

/// Turn Outlook automatic replies (Out of Office) on or off from Siri,
/// Shortcuts, an interactive widget button, or a Control Center control.
/// Uses the app's default Out of Office message when enabling; an existing
/// message set elsewhere is preserved.
///
/// Source file shared (dual target membership) between the app and the
/// widget extension so Siri/Shortcuts and the widget's buttons both have
/// the type. The system background-launches the app to run `perform()`,
/// where the `StatusActions` dependency resolves to the live `Inbox`.
struct SetOutOfOfficeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Out of Office"
    static var description = IntentDescription(
        "Turn your Outlook automatic replies (Out of Office) on or off."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Turn On", default: true)
    var turnOn: Bool

    @Dependency var actions: StatusActions

    init() {}

    init(turnOn: Bool) {
        self.turnOn = turnOn
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set Out of Office \(\.$turnOn)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await actions.applyOutOfOffice(turnOn)
        let dialog: IntentDialog = turnOn
            ? "Out of Office is now on."
            : "Out of Office is now off."
        return .result(dialog: dialog)
    }
}
