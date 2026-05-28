// CheckInShortcuts.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Surfaces CheckIn's intents to Siri and Spotlight with spoken phrases.
/// Every phrase must contain the `\(.applicationName)` token — the
/// framework requires it so Siri can disambiguate which app to invoke.
struct CheckInShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetStatusIntent(),
            phrases: [
                "Set my status to \(\.$status) in the \(.applicationName) app",
                "Set my status in the \(.applicationName) app",
                "Change my status in the \(.applicationName) app",
            ],
            shortTitle: "Set Status",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: NextMeetingIntent(),
            phrases: [
                "What's my next meeting in the \(.applicationName) app",
                "When's my next meeting in the \(.applicationName) app",
            ],
            shortTitle: "Next Meeting",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(turnOn: true),
            phrases: [
                "Turn on my Out of Office in the \(.applicationName) app",
                "Set my Out of Office on in the \(.applicationName) app",
            ],
            shortTitle: "Turn On Out of Office",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(turnOn: false),
            phrases: [
                "Turn off my Out of Office in the \(.applicationName) app",
                "Set my Out of Office off in the \(.applicationName) app",
            ],
            shortTitle: "Turn Off Out of Office",
            systemImageName: "envelope.open"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadEmails),
            phrases: [
                "How many unread emails do I have in the \(.applicationName) app",
                "How many unread emails in the \(.applicationName) app",
            ],
            shortTitle: "Unread Emails",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadChats),
            phrases: [
                "How many unread chats do I have in the \(.applicationName) app",
                "How many unread chats in the \(.applicationName) app",
            ],
            shortTitle: "Unread Chats",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .remainingMeetings),
            phrases: [
                "How many more meetings today in the \(.applicationName) app",
                "How many meetings do I have left in the \(.applicationName) app",
            ],
            shortTitle: "Remaining Meetings",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadMessages),
            phrases: [
                "How many unread messages do I have in the \(.applicationName) app",
                "How many unread messages in the \(.applicationName) app",
            ],
            shortTitle: "Unread Messages",
            systemImageName: "tray.full"
        )
    }
}
