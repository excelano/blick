// CheckInSummary.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct CheckInSummary {
    /// Next or in-progress meeting. Gets the full MeetingCard treatment
    /// (RSVP, conflict warning).
    var meeting: Meeting?
    /// The rest of today's attendable meetings, ordered by start time.
    /// Rendered as compact rows below the main meeting card.
    var laterToday: [Meeting]
    var emails: [Email]
    var chats: [ChatMessage]
    /// Total unread across the mailbox. `emails` is capped at 20 newest;
    /// the section footer uses `totalUnreadEmails - emails.count` to show
    /// "X more unread" when there are more than we render.
    var totalUnreadEmails: Int
}
