// WorkdaySummaryIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Speak a work-day overview from Siri, Shortcuts, or Spotlight, with
/// optional progressive disclosure over up to three levels:
///
/// 1. Headline — the next meeting and the unread-message counts.
/// 2. On "yes" — who the unread chats and emails are from, plus how many
///    meetings remain today.
/// 3. On a second "yes" — each remaining meeting by name and time.
///
/// Each step past the headline is gated by a Siri yes/no via
/// `requestConfirmation`, so a plain "What's my Blick" stays a one-line
/// answer unless the user asks to go deeper. Wording is shared through
/// `IntentSpeech` / `StatusSpeech`. Runs headless; one refresh feeds it all.
/// iPhone only — the watch work-day intent stays single-shot, since its
/// headless snapshot reads can't carry an interactive follow-up.
struct WorkdaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Work Day Summary"
    static var description = IntentDescription(
        "Hear your next meeting and unread messages together."
    )
    static var openAppWhenRun = false

    @Dependency var inbox: Inbox

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await inbox.refreshForIntent()

        let emails = inbox.unreadEmailCount
        let chats = inbox.unreadChatCount
        let remaining = (inbox.nextMeeting.map { [$0] } ?? []) + inbox.laterToday

        // Level 1: the headline — next meeting and unread-message counts.
        let headline = IntentSpeech.workdaySummary(inbox.nextMeeting, emails: emails, chats: chats)

        // Nothing to drill into — stop at the headline.
        guard emails + chats > 0 || !remaining.isEmpty else {
            return .result(dialog: "\(headline)")
        }

        // Offer Level 2.
        try await requestConfirmation(result: .result(dialog: "\(headline) Want to hear the breakdown?"))

        // Level 2: who the unread messages are from, plus how many meetings remain.
        let rows = inbox.summary
        let senders = IntentSpeech.unreadSenders(
            chatSenders: rows?.chats.map(\.from) ?? [],
            chatCount: chats,
            emailSenders: rows?.emails.map(\.from) ?? [],
            emailCount: emails,
            emailsCapped: emails > (rows?.emails.count ?? 0)
        )
        let level2 = "\(senders) \(IntentSpeech.remainingMeetings(remaining.count))"

        // No meetings to detail — stop at Level 2.
        guard !remaining.isEmpty else {
            return .result(dialog: "\(level2)")
        }

        // Offer Level 3.
        try await requestConfirmation(result: .result(dialog: "\(level2) Want the meeting times?"))

        // Level 3: each remaining meeting by name and time.
        return .result(dialog: "\(IntentSpeech.meetingList(remaining))")
    }
}
