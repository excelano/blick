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
            ? "Your status isn't set — Microsoft 365 is showing it automatically."
            : "You're showing as \(presence.displayName)."
    }

    /// Confirmation spoken after setting a presence (or resetting to auto).
    public static func setPresenceConfirmation(_ presence: Presence) -> String {
        presence == .unknown
            ? "Your CheckIn status is back to automatic."
            : "Your CheckIn status is now \(presence.displayName)."
    }

    /// Confirmation spoken after toggling Out of Office.
    public static func outOfOfficeConfirmation(_ on: Bool) -> String {
        on ? "Out of Office is now on." : "Out of Office is now off."
    }
}
