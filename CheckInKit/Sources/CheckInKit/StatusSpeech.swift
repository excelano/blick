// StatusSpeech.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The canonical wording for CheckIn's spoken status, shared across every
/// surface that has to say it: the phone's App Intents (via the app's thin
/// `IntentSpeech` facade), the phone's Set Presence / Set Out-of-Office
/// confirmations, and the watch's Siri intents (which read straight from the
/// pushed snapshot). Keeping the strings here, built from primitives and
/// `Presence`, means the watch and phone can never say the same thing two
/// different ways.
public enum StatusSpeech {
    /// "You have no Xs." / "You have 1 X." / "You have N Xs."
    public static func count(_ n: Int, singular: String, plural: String) -> String {
        switch n {
        case 0: return "You have no \(plural)."
        case 1: return "You have 1 \(singular)."
        default: return "You have \(n) \(plural)."
        }
    }

    /// "Your next meeting is X at 2:00 PM." or, with no subject/start,
    /// "You have no more meetings today."
    public static func nextMeeting(subject: String?, start: Date?) -> String {
        guard let subject, let start else {
            return "You have no more meetings today."
        }
        let time = start.formatted(date: .omitted, time: .shortened)
        return "Your next meeting is \(subject) at \(time)."
    }

    /// "You have no more meetings today." / "...1 more meeting..." / "...N more..."
    public static func remainingMeetings(_ n: Int) -> String {
        switch n {
        case 0: return "You have no more meetings today."
        case 1: return "You have 1 more meeting today."
        default: return "You have \(n) more meetings today."
        }
    }

    /// Unread emails from one sender — the from-a-sender twin of `count`.
    public static func unreadFromSender(_ n: Int, sender: String) -> String {
        switch n {
        case 0: return "You have no unread emails from \(sender)."
        case 1: return "You have 1 unread email from \(sender)."
        default: return "You have \(n) unread emails from \(sender)."
        }
    }

    /// The work-day overview: the next-meeting sentence followed by the
    /// unread-messages sentence, as one spoken line. Shared by the phone and
    /// watch work-day intents so their separator and order can't drift.
    public static func workdaySummary(meetingSubject: String?, meetingStart: Date?, emails: Int, chats: Int) -> String {
        "\(nextMeeting(subject: meetingSubject, start: meetingStart)) \(unreadMessages(emails: emails, chats: chats))"
    }

    /// The combined unread-messages sentence (emails plus chats).
    public static func unreadMessages(emails: Int, chats: Int) -> String {
        switch (emails, chats) {
        case (0, 0):
            return "You're all caught up — no unread messages."
        case (let e, 0):
            return count(e, singular: "unread email", plural: "unread emails")
        case (0, let c):
            return count(c, singular: "unread chat", plural: "unread chats")
        default:
            let e = emails == 1 ? "1 email" : "\(emails) emails"
            let c = chats == 1 ? "1 chat" : "\(chats) chats"
            return "You have \(emails + chats) unread messages: \(e) and \(c)."
        }
    }

    /// The current-presence sentence, Out-of-Office-dominant to match how the
    /// glance and widget render state. `.unknown` means "no preference set"
    /// rather than a real status, so it reads as automatic.
    public static func currentPresence(_ presence: Presence, isOutOfOffice: Bool) -> String {
        if isOutOfOffice {
            return presence == .unknown
                ? "Out of office is on."
                : "Out of office is on, and you're showing as \(presence.displayName)."
        }
        return presence == .unknown
            ? "Your presence isn't set — Microsoft 365 is showing it automatically."
            : "You're showing as \(presence.displayName)."
    }

    /// Confirmation spoken after setting a presence (or resetting to auto).
    public static func setPresenceConfirmation(_ presence: Presence) -> String {
        presence == .unknown
            ? "Your Blick presence is back to automatic."
            : "Your Blick presence is now \(presence.displayName)."
    }

    /// Confirmation spoken after toggling Out of Office.
    public static func outOfOfficeConfirmation(_ on: Bool) -> String {
        on ? "Out of Office is now on." : "Out of Office is now off."
    }

    /// Level 2 of the work-day breakdown: who the unread messages are from.
    /// Groups by distinct sender in arrival order, e.g. "Your 5 chats are from
    /// Bob, Stan, and Sarah. Your 3 emails are from Microsoft and John." A true
    /// `emailsCapped` means more unread emails exist than were sampled, so the
    /// named senders close with "and others".
    public static func unreadSenders(chatSenders: [String], chatCount: Int,
                                     emailSenders: [String], emailCount: Int,
                                     emailsCapped: Bool) -> String {
        var clauses: [String] = []
        if chatCount > 0 {
            clauses.append(senderClause(count: chatCount, noun: "chat",
                                        senders: chatSenders, capped: false))
        }
        if emailCount > 0 {
            clauses.append(senderClause(count: emailCount, noun: "email",
                                        senders: emailSenders, capped: emailsCapped))
        }
        return clauses.isEmpty ? "You have no unread messages." : clauses.joined(separator: " ")
    }

    /// Level 3: each remaining meeting by name and time, e.g. "Standup at
    /// 9:00 AM, Design review at 11:00 AM, and your 1:1 at 3:00 PM." Times use
    /// the same format as `nextMeeting` so the surfaces never disagree.
    public static func meetingList(_ meetings: [(subject: String, start: Date)]) -> String {
        guard !meetings.isEmpty else { return "You have no more meetings today." }
        let items = meetings.map {
            "\($0.subject) at \($0.start.formatted(date: .omitted, time: .shortened))"
        }
        return englishList(items) + "."
    }

    // MARK: - Voice catch-up (read-aloud)

    /// How many unread items the read-aloud walk speaks in one session.
    public static let readAloudCap = 5

    /// Longest spoken preview per item, in characters, trimmed at a word
    /// boundary. `Email.preview` is Graph `bodyPreview` (~255 chars); a full
    /// read of untrimmed previews is a minute-plus of speech. Both constants
    /// live here so they can be tuned in one place after on-device listening.
    public static let spokenSnippetLimit = 160

    /// Build the read-aloud content: one spoken line per unread item, chats
    /// first then emails, capped at `readAloudCap` items total. Returns the
    /// ordered lines (the intent joins them into one spoken block) plus an
    /// optional overflow tail naming how much went unread past the cap.
    /// `chatTotal` / `emailTotal` are the true unread counts (the arrays are
    /// already capped upstream, so the tail is computed from the totals).
    public static func readAloud(
        chats: [(from: String, preview: String)],
        chatTotal: Int,
        emails: [(from: String, subject: String, preview: String)],
        emailTotal: Int
    ) -> (lines: [String], overflow: String?) {
        let chatsRead = Array(chats.prefix(readAloudCap))
        let emailsRead = Array(emails.prefix(max(0, readAloudCap - chatsRead.count)))

        let lines = chatsRead.map { chatLine(from: $0.from, preview: $0.preview) }
            + emailsRead.map { emailLine(from: $0.from, subject: $0.subject, preview: $0.preview) }

        let moreChats = max(0, chatTotal - chatsRead.count)
        let moreEmails = max(0, emailTotal - emailsRead.count)
        return (lines, overflowTail(moreChats: moreChats, moreEmails: moreEmails))
    }

    // MARK: - Private list helpers

    private static func chatLine(from: String, preview: String) -> String {
        let snippet = spokenSnippet(preview)
        let who = spokenSender(from)
        return snippet.isEmpty ? "Teams from \(who)." : "Teams from \(who): \(snippet)."
    }

    private static func emailLine(from: String, subject: String, preview: String) -> String {
        let who = spokenSender(from)
        let subj = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = subj.isEmpty ? "Email from \(who)" : "Email from \(who), \(subj)"
        let snippet = spokenSnippet(preview)
        return snippet.isEmpty ? "\(head)." : "\(head): \(snippet)."
    }

    private static func spokenSender(_ from: String) -> String {
        let trimmed = from.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "someone" : trimmed
    }

    /// Collapse whitespace, trim to `spokenSnippetLimit` at a word boundary,
    /// and strip trailing punctuation so the line's own period reads cleanly.
    /// No ellipsis — Siri voices a trailing "…" as literal noise.
    private static func spokenSnippet(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let clipped: String
        if collapsed.count > spokenSnippetLimit {
            let cutoff = collapsed.index(collapsed.startIndex, offsetBy: spokenSnippetLimit)
            let head = collapsed[..<cutoff]
            clipped = String(head[..<(head.lastIndex(of: " ") ?? head.endIndex)])
        } else {
            clipped = collapsed
        }
        return clipped.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?"))
    }

    private static func overflowTail(moreChats: Int, moreEmails: Int) -> String? {
        var parts: [String] = []
        if moreChats > 0 { parts.append(moreChats == 1 ? "1 more chat" : "\(moreChats) more chats") }
        if moreEmails > 0 { parts.append(moreEmails == 1 ? "1 more email" : "\(moreEmails) more emails") }
        return parts.isEmpty ? nil : "And \(englishList(parts)) unread."
    }

    private static func senderClause(count: Int, noun: String,
                                     senders: [String], capped: Bool) -> String {
        var names = orderedDistinct(senders)
        if capped { names.append("others") }
        let plural = count == 1 ? noun : "\(noun)s"
        let verb = count == 1 ? "is" : "are"
        let who = names.isEmpty ? "someone" : englishList(names)
        return "Your \(count) \(plural) \(verb) from \(who)."
    }

    /// Distinct, first-seen order preserved, blanks dropped.
    private static func orderedDistinct(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    /// "A" / "A and B" / "A, B, and C" (Oxford comma).
    private static func englishList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")), and \(items.last!)"
        }
    }
}
