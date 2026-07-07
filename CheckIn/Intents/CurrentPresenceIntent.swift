// CurrentPresenceIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit

/// Read back the user's current Microsoft 365 presence (and whether
/// Out-of-Office is on) from Siri, Shortcuts, or Spotlight, then offer a
/// one-tap flip: a Siri yes/no to switch to Available — or, when already
/// Available, to Do Not Disturb — applied through the same `StatusActions`
/// path as `SetPresenceIntent`. Runs headless. On confirm it returns the
/// new presence name as a value for Shortcuts to chain on; declining just
/// leaves the spoken status as the answer.
struct CurrentPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Current Presence"
    static var description = IntentDescription("Check your current Microsoft 365 presence, and optionally switch it.")
    static var openAppWhenRun = false

    @Dependency var inbox: Inbox
    @Dependency var actions: StatusActions

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await inbox.refreshForIntent()

        let presence = inbox.currentPresence
        let statement = IntentSpeech.currentPresence(presence, isOutOfOffice: inbox.isOutOfOffice)

        // After reporting, offer a one-tap flip: anything but Available flips to
        // Available; Available flips to Do Not Disturb.
        let target: Presence = presence == .available ? .doNotDisturb : .available

        try await requestConfirmation(
            dialog: "\(statement) Shall I change it to \(target.displayName)?"
        )

        // Confirmed — apply it (read-back + widget/watch sync) and report the new state.
        try await actions.applyPresence(target)
        return .result(value: target.displayName,
                       dialog: "\(StatusSpeech.setPresenceConfirmation(target))")
    }
}
