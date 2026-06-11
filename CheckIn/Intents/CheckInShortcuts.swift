// CheckInShortcuts.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Surfaces the app's intents to Siri and Spotlight with spoken phrases.
/// Every phrase must contain the `\(.applicationName)` token — the
/// framework requires it so Siri can disambiguate which app to invoke.
/// Because the app name ("Blick") is a real noun, the token reads as
/// natural language: the work-day overview is "What's my \(.applicationName)"
/// ("What's my Blick"), and specific queries simply trail "in \(.applicationName)".
/// Phrases keep both "status" and "presence" wordings because users say
/// both; the extra variants cost nothing and improve Siri's match rate.
struct CheckInShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPresenceIntent(),
            phrases: [
                "Set my presence to \(\.$status) in \(.applicationName)",
                "Change my presence to \(\.$status) in \(.applicationName)",
                "Mark me as \(\.$status) in \(.applicationName)",
                "I'm \(\.$status) in \(.applicationName)",
                "I'm now \(\.$status) in \(.applicationName)",
                "I'll \(\.$status) in \(.applicationName)",
                "Go \(\.$status) in \(.applicationName)",
                "Set my status to \(\.$status) in \(.applicationName)",
                "Set my status in \(.applicationName)",
                "Change my status in \(.applicationName)",
                "\(\.$status) in \(.applicationName)",
                "\(\.$status) me in \(.applicationName)",
            ],
            shortTitle: "Set Presence",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: CurrentPresenceIntent(),
            phrases: [
                "What's my presence in \(.applicationName)",
                "What's my status in \(.applicationName)",
                "What's my current status in \(.applicationName)",
                "What am I set to in \(.applicationName)",
            ],
            shortTitle: "My Presence",
            systemImageName: "person.crop.circle.fill"
        )
        AppShortcut(
            intent: NextMeetingIntent(),
            phrases: [
                "What's my next meeting in \(.applicationName)",
                "When's my next meeting in \(.applicationName)",
                "What's coming up next in \(.applicationName)",
                "What's my next call in \(.applicationName)",
            ],
            shortTitle: "Next Meeting",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(value: true),
            phrases: [
                "Turn on my Out of Office in \(.applicationName)",
                "Set my Out of Office on in \(.applicationName)",
                "Enable my Out of Office in \(.applicationName)",
                "Set me to out of office in \(.applicationName)",
            ],
            shortTitle: "Turn On Out of Office",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(value: false),
            phrases: [
                "Turn off my Out of Office in \(.applicationName)",
                "Set my Out of Office off in \(.applicationName)",
                "Disable my Out of Office in \(.applicationName)",
                "Clear my Out of Office in \(.applicationName)",
            ],
            shortTitle: "Turn Off Out of Office",
            systemImageName: "envelope.open"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadEmails),
            phrases: [
                "How many unread emails do I have in \(.applicationName)",
                "How many unread emails in \(.applicationName)",
                "Do I have any unread emails in \(.applicationName)",
                "Any unread emails in \(.applicationName)",
            ],
            shortTitle: "Unread Emails",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadChats),
            phrases: [
                "How many unread chats do I have in \(.applicationName)",
                "How many unread chats in \(.applicationName)",
                "Do I have any unread chats in \(.applicationName)",
            ],
            shortTitle: "Unread Chats",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .remainingMeetings),
            phrases: [
                "How many more meetings today in \(.applicationName)",
                "How many meetings do I have left in \(.applicationName)",
                "How many meetings are left today in \(.applicationName)",
                "Do I have more meetings today in \(.applicationName)",
            ],
            shortTitle: "Remaining Meetings",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadMessages),
            phrases: [
                "How many unread messages do I have in \(.applicationName)",
                "How many unread messages in \(.applicationName)",
                "Do I have any unread messages in \(.applicationName)",
                "Am I caught up in \(.applicationName)",
            ],
            shortTitle: "Unread Messages",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: WorkdaySummaryIntent(),
            phrases: [
                "What's my \(.applicationName)",
                "Show me my \(.applicationName)",
                "What's today's \(.applicationName)",
                "Give me my \(.applicationName)",
                "What's my work day like in \(.applicationName)",
                "What's on my plate in \(.applicationName)",
                "Give me an overview in \(.applicationName)",
                "Catch me up in \(.applicationName)",
            ],
            shortTitle: "Work Day",
            systemImageName: "list.bullet.clipboard"
        )
    }
}
