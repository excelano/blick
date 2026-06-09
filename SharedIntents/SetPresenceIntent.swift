// SetPresenceIntent.swift
// SharedIntents
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit

/// Set the user's preferred Microsoft 365 presence (or reset to automatic) from
/// Siri, Shortcuts, an interactive widget button, or a Control Center
/// control. Runs headless — no app UI.
///
/// Source file shared (dual target membership) between the app and the
/// widget extension so Siri/Shortcuts (app target) and the widget's
/// buttons (extension target) both have the type. On iOS 18+ a widget
/// `Button(intent:)` runs `perform()` in the extension process, not the
/// app, so `StatusActions` is registered in both — app-side wired to
/// `Inbox`, extension-side wired to a lean presence client — and the
/// `@Dependency` resolves to whichever process the intent fires in.
///
/// CheckIn keeps its own presence session alive, so a pinned presence takes
/// effect without a Teams desktop session running. `applyPresence` reads the
/// presence back after writing and throws when Microsoft didn't honor the
/// request (tenant policy, Conditional Access, or another client overriding),
/// so this intent only speaks success when the status actually changed.
struct SetPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Presence"
    static var description = IntentDescription(
        "Set your Microsoft 365 status, or reset it to automatic."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Presence")
    var status: StatusAppEnum

    @Dependency var actions: StatusActions

    init() {}

    init(status: StatusAppEnum) {
        self.status = status
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set my presence to \(\.$status)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await actions.applyPresence(status.asPresence)
        return .result(dialog: "\(StatusSpeech.setPresenceConfirmation(status.asPresence))")
    }
}
