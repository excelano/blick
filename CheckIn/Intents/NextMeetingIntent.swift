// NextMeetingIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Read the user's next meeting today from Siri, Shortcuts, or Spotlight
/// and speak it back. Runs headless.
///
/// A background-launched intent starts with empty in-memory state, so a
/// refresh is required before reading `nextMeeting`. This does the app's
/// full fetch for a single meeting read — acceptable for v1; a targeted
/// meetings-only fetch is a later optimization.
struct NextMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Meeting"
    static var description = IntentDescription("Check your next meeting today.")
    static var openAppWhenRun = false

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.refresh()

        guard let meeting = inbox.nextMeeting else {
            return .result(dialog: "You have no more meetings today.")
        }
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        let dialog: IntentDialog = "Your next meeting is \(meeting.subject) at \(time)."
        return .result(dialog: dialog)
    }
}
