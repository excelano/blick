// IntentSpeech.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation

/// App-side facade over `StatusSpeech` (CheckInKit) for the phone's App
/// Intents. The canonical wording lives in `StatusSpeech` so the watch
/// phrases things identically; these forwarders just adapt the app's own
/// `Meeting` view model and keep the call sites in the intents unchanged.
enum IntentSpeech {
    static func count(_ n: Int, singular: String, plural: String) -> String {
        StatusSpeech.count(n, singular: singular, plural: plural)
    }

    static func nextMeeting(_ meeting: Meeting?) -> String {
        StatusSpeech.nextMeeting(subject: meeting?.subject, start: meeting?.start)
    }

    static func unreadFromSender(_ n: Int, sender: String) -> String {
        StatusSpeech.unreadFromSender(n, sender: sender)
    }

    static func workdaySummary(_ meeting: Meeting?, emails: Int, chats: Int) -> String {
        StatusSpeech.workdaySummary(
            meetingSubject: meeting?.subject, meetingStart: meeting?.start,
            emails: emails, chats: chats
        )
    }

    static func remainingMeetings(_ n: Int) -> String {
        StatusSpeech.remainingMeetings(n)
    }

    static func unreadMessages(emails: Int, chats: Int) -> String {
        StatusSpeech.unreadMessages(emails: emails, chats: chats)
    }

    static func currentPresence(_ presence: Presence, isOutOfOffice: Bool) -> String {
        StatusSpeech.currentPresence(presence, isOutOfOffice: isOutOfOffice)
    }

    static func unreadSenders(chatSenders: [String], chatCount: Int,
                              emailSenders: [String], emailCount: Int,
                              emailsCapped: Bool) -> String {
        StatusSpeech.unreadSenders(chatSenders: chatSenders, chatCount: chatCount,
                                   emailSenders: emailSenders, emailCount: emailCount,
                                   emailsCapped: emailsCapped)
    }

    static func meetingList(_ meetings: [Meeting]) -> String {
        StatusSpeech.meetingList(meetings.map { (subject: $0.subject, start: $0.start) })
    }
}
