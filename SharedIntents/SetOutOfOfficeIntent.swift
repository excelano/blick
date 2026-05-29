// SetOutOfOfficeIntent.swift
// SharedIntents
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
/// the type. On iOS 18+ a widget `Toggle(intent:)` runs `perform()` in
/// the extension process, not the app, so `StatusActions` is registered
/// in both — app-side wired to `Inbox`, extension-side wired to a lean
/// presence client — and the `@Dependency` resolves to whichever process
/// the intent fires in.
struct SetOutOfOfficeIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Set Out of Office"
    static var description = IntentDescription(
        "Turn your Outlook automatic replies (Out of Office) on or off."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Turn On", default: true)
    var value: Bool

    @Dependency var actions: StatusActions

    init() {}

    init(value: Bool) {
        self.value = value
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set Out of Office \(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await actions.applyOutOfOffice(value)
        let dialog: IntentDialog = value
            ? "Out of Office is now on."
            : "Out of Office is now off."
        return .result(dialog: dialog)
    }
}
