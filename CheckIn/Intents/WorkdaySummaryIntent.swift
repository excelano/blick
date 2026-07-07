// WorkdaySummaryIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Speak a work-day overview from Siri, Shortcuts, or Spotlight, with
/// optional progressive disclosure:
///
/// 1. Headline — the next meeting and the unread-message counts.
/// 2. On "yes" — who the unread chats and emails are from.
/// 3. On "yes" to "read them?" — the unread queue read aloud (chats first,
///    then emails), capped, as one block, plus how much went unread past it.
/// 4. On "yes" to "meeting times?" — each remaining meeting by name and time.
///
/// The read is offered before the meeting times because reading the messages
/// is the point of "catch me up"; the who-from digest still comes first so the
/// plain "What's my Blick" phrase keeps its summary. Each step is a linear
/// `requestConfirmation` yes/no — App Intents resolves a request by its source
/// call site, so a *dynamic loop* of per-item prompts collapses to one identity
/// and repeats; the read is therefore one block, not an item-by-item walk.
/// Wording is shared through `IntentSpeech` / `StatusSpeech`. Runs headless;
/// one refresh feeds it all. iPhone only — the watch work-day intent stays
/// single-shot, since its headless snapshot reads can't carry a follow-up.
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
        try await requestConfirmation(dialog: "\(headline) Want to hear the breakdown?")

        // Level 2: who the unread messages are from. The read offer follows
        // this digest directly so "read them?" clearly refers to the messages;
        // the meeting count is held back to the meeting-times gate below.
        let rows = inbox.summary
        let senders = IntentSpeech.unreadSenders(
            chatSenders: rows?.chats.map(\.from) ?? [],
            chatCount: chats,
            emailSenders: rows?.emails.map(\.from) ?? [],
            emailCount: emails,
            emailsCapped: emails > (rows?.emails.count ?? 0)
        )

        // Level 3: the read-aloud block, offered before the meeting times.
        // `afterRead` carries whatever should precede the meeting gate — the
        // read block when there were messages, or the digest itself when there
        // were none (so the who-from line still gets spoken).
        let afterRead: String
        if emails + chats > 0 {
            try await requestConfirmation(dialog: "\(senders) Want me to read them?")

            let (lines, overflow) = IntentSpeech.readAloud(
                chats: rows?.chats ?? [], chatTotal: chats,
                emails: rows?.emails ?? [], emailTotal: emails
            )
            let block = (lines + (overflow.map { [$0] } ?? [])).joined(separator: " ")
            afterRead = block.isEmpty ? senders : block
        } else {
            afterRead = senders
        }

        // No meetings to detail — close on the read block (or the digest).
        // `remaining` is guaranteed non-empty when there were no messages, per
        // the top guard, so this only fires when there was a read.
        guard !remaining.isEmpty else {
            return .result(dialog: "\(afterRead)")
        }

        // Level 4: the meeting count and the times, gated.
        let meetings = "\(IntentSpeech.remainingMeetings(remaining.count)) Want the meeting times?"
        try await requestConfirmation(dialog: "\(afterRead) \(meetings)")
        return .result(dialog: "\(IntentSpeech.meetingList(remaining))")
    }
}
