// CheckInKitTests.swift
// CheckInKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckInKit

/// Records the values forwarded through a `StatusActions` box.
@MainActor
final class StatusRecorder {
    var appliedPresence: Presence?
    var appliedOutOfOffice: Bool?
}

@MainActor
struct StatusActionsTests {
    /// `StatusActions` forwards each call to the handler the app wired in.
    /// (The intents' `@Dependency` resolution can't be unit-tested —
    /// `@Dependency` is injected only when the system runs an intent, not
    /// when `perform()` is called directly — so that path is verified
    /// on-device via Siri / the widget instead.)
    @Test func statusActionsForwardToHandlers() async throws {
        let recorder = StatusRecorder()
        let actions = StatusActions(
            presence: { recorder.appliedPresence = $0 },
            outOfOffice: { recorder.appliedOutOfOffice = $0 }
        )

        try await actions.applyPresence(.busy)
        try await actions.applyOutOfOffice(true)

        #expect(recorder.appliedPresence == .busy)
        #expect(recorder.appliedOutOfOffice == true)
    }
}
