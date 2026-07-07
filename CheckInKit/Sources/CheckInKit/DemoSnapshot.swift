// DemoSnapshot.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// The sample status snapshot for demo/screenshot mode, matching the phone's
// demo day (see the app's DemoData). Used by surfaces that render a snapshot
// directly rather than an Inbox — the watch glance seeds this on a `--demo`
// launch, standing in for a WatchConnectivity push. Compiled out of release.

#if DEBUG
import Foundation

public enum DemoSnapshot {
    private static func fromNow(_ minutes: Double) -> Date {
        Date().addingTimeInterval(minutes * 60)
    }

    private static func ago(_ minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    /// A professional sample day: an upcoming steering-committee review, two
    /// later meetings, three unread Teams chats, and the top unread mail.
    public static var snapshot: CheckInSnapshot {
        CheckInSnapshot(
            updatedAt: Date(),
            nextMeetingSubject: "Portfolio Review — Steering Committee",
            nextMeetingStart: fromNow(25),
            nextMeetingEnd: fromNow(55),
            nextMeetingOrganizer: "Elena Fischer",
            nextMeetingJoinUrl: "https://teams.microsoft.com/l/meetup-join/demo1",
            unreadEmailCount: 14,
            chatCount: 3,
            presence: .available,
            isOutOfOffice: false,
            laterMeetings: [
                SnapshotMeeting(
                    subject: "1:1 with Marcus Reid",
                    start: fromNow(180), end: fromNow(210),
                    organizer: "Marcus Reid",
                    joinUrl: "https://teams.microsoft.com/l/meetup-join/demo2"
                ),
                SnapshotMeeting(
                    subject: "Vendor Risk Assessment Walkthrough",
                    start: fromNow(300), end: fromNow(345),
                    organizer: "Priya Nair",
                    joinUrl: "https://teams.microsoft.com/l/meetup-join/demo3"
                )
            ],
            topEmails: [
                SnapshotEmail(id: "demo-mail-1", sender: "Marcus Reid",
                              subject: "Re: FY26 budget scenarios",
                              preview: "I pushed the revised model to the shared drive — can you sanity-check the licensing line before Thursday?",
                              received: ago(14), isFlagged: true),
                SnapshotEmail(id: "demo-mail-2", sender: "Elena Fischer",
                              subject: "Steering committee deck (v3)",
                              preview: "Latest slides attached. I tightened the roadmap section per your notes from Friday.",
                              received: ago(52)),
                SnapshotEmail(id: "demo-mail-3", sender: "Priya Nair",
                              subject: "Vendor risk: SOC 2 gaps",
                              preview: "Two findings need a response owner before we can sign off. Details inside.",
                              received: ago(96)),
                SnapshotEmail(id: "demo-mail-4", sender: "IT Governance",
                              subject: "Action required: data retention policy sign-off",
                              preview: "Your review is the last one outstanding for the Q3 attestation.",
                              received: ago(140))
            ],
            topChats: [
                SnapshotChat(id: "demo-chat-1", sender: "Marcus Reid",
                             preview: "Did the budget numbers land ok?", sent: ago(6)),
                SnapshotChat(id: "demo-chat-2", sender: "Priya Nair",
                             preview: "Thanks — that unblocks the sign-off.", sent: ago(38)),
                SnapshotChat(id: "demo-chat-3", sender: "Elena Fischer",
                             preview: "Sending the deck in five.", sent: ago(72))
            ]
        )
    }
}
#endif
