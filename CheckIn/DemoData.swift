// DemoData.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// The sample account state shown in demo/screenshot mode: presence, today's
// meetings, unread mail, and Teams chats. Professional, work-shaped content with
// invented people and no real data. Seeded straight into `Inbox` (see
// `Inbox.loadDemo()`), which then publishes the matching App Group snapshot so
// the widget and watch show the same day. Compiled out of release builds.

#if DEBUG
import CheckInKit
import Foundation
import KlartextUI

enum DemoData {
    /// The signed-in user's presence and status line for the demo day.
    static let presence: Presence = .available
    static let customStatusMessage = "Heads-down until noon"
    static let isOutOfOffice = false

    /// Unread mail is capped at what the summary renders; the header shows
    /// "+ N more unread" from this total minus the visible rows.
    static let totalUnreadEmails = 14

    /// A time `minutes` from now, for staging the day around the current clock
    /// so the "next meeting" is always genuinely upcoming in a screenshot.
    private static func fromNow(_ minutes: Double) -> Date {
        Date().addingTimeInterval(minutes * 60)
    }

    private static func ago(_ minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    static var nextMeeting: Meeting {
        Meeting(
            id: "demo-mtg-1",
            subject: "Portfolio Review — Steering Committee",
            organizer: "Elena Fischer",
            organizerEmail: "elena.fischer@northwind.example",
            start: fromNow(25),
            end: fromNow(55),
            joinUrl: "https://teams.microsoft.com/l/meetup-join/demo1",
            responseStatus: .accepted,
            hasConflict: false,
            iCalUId: nil
        )
    }

    static var laterMeetings: [Meeting] {
        [
            Meeting(
                id: "demo-mtg-2",
                subject: "1:1 with Marcus Reid",
                organizer: "Marcus Reid",
                organizerEmail: "marcus.reid@northwind.example",
                start: fromNow(180),
                end: fromNow(210),
                joinUrl: "https://teams.microsoft.com/l/meetup-join/demo2",
                responseStatus: .accepted,
                hasConflict: false,
                iCalUId: nil
            ),
            Meeting(
                id: "demo-mtg-3",
                subject: "Vendor Risk Assessment Walkthrough",
                organizer: "Priya Nair",
                organizerEmail: "priya.nair@northwind.example",
                start: fromNow(300),
                end: fromNow(345),
                joinUrl: "https://teams.microsoft.com/l/meetup-join/demo3",
                responseStatus: .tentativelyAccepted,
                hasConflict: false,
                iCalUId: nil
            )
        ]
    }

    private static func email(
        _ id: String,
        from: String,
        address: String,
        subject: String,
        preview: String,
        minutesAgo: Double,
        isFlagged: Bool = false,
        isRead: Bool = false
    ) -> Email {
        Email(
            id: id,
            subject: subject,
            from: from,
            fromAddress: address,
            preview: preview,
            received: ago(minutesAgo),
            isRead: isRead,
            isFlagged: isFlagged
        )
    }

    static var emails: [Email] {
        [
            email("demo-mail-1", from: "Marcus Reid", address: "marcus.reid@northwind.example",
                  subject: "Re: FY26 budget scenarios",
                  preview: "I pushed the revised model to the shared drive — can you sanity-check the licensing line before Thursday?",
                  minutesAgo: 14, isFlagged: true),
            email("demo-mail-2", from: "Elena Fischer", address: "elena.fischer@northwind.example",
                  subject: "Steering committee deck (v3)",
                  preview: "Latest slides attached. I tightened the roadmap section per your notes from Friday.",
                  minutesAgo: 52),
            email("demo-mail-3", from: "Priya Nair", address: "priya.nair@northwind.example",
                  subject: "Vendor risk: SOC 2 gaps",
                  preview: "Two findings need a response owner before we can sign off. Details and my suggested owners inside.",
                  minutesAgo: 96),
            email("demo-mail-4", from: "IT Governance", address: "governance@northwind.example",
                  subject: "Action required: data retention policy sign-off",
                  preview: "Your review is the last one outstanding for the Q3 attestation. The window closes Friday.",
                  minutesAgo: 140),
            email("demo-mail-5", from: "Sofia Delgado", address: "sofia.delgado@northwind.example",
                  subject: "Notes from the architecture review",
                  preview: "Summary and decisions from this morning, plus the three open questions we still owe the team.",
                  minutesAgo: 205),
            email("demo-mail-6", from: "Daniel Okafor", address: "daniel.okafor@northwind.example",
                  subject: "Contract renewal — CloudScale",
                  preview: "They came back with a 9% increase. I think we have room to push back; here's what comparable teams pay.",
                  minutesAgo: 320)
        ]
    }

    /// The full-inbox browse list (read and unread, newest first) behind the
    /// Email header — the unread front plus a few already-read messages so the
    /// browse view and its search read like a real mailbox.
    static var browseEmails: [Email] {
        emails + [
            email("demo-mail-7", from: "Calendar", address: "calendar@northwind.example",
                  subject: "Accepted: Architecture review",
                  preview: "Sofia Delgado has accepted your invitation.",
                  minutesAgo: 400, isRead: true),
            email("demo-mail-8", from: "Elena Fischer", address: "elena.fischer@northwind.example",
                  subject: "Thanks for the quick turnaround",
                  preview: "That's exactly what I needed — appreciate it.",
                  minutesAgo: 520, isRead: true),
            email("demo-mail-9", from: "CloudScale Billing", address: "billing@cloudscale.example",
                  subject: "Your July invoice is ready",
                  preview: "Invoice #4471 is available in your account portal.",
                  minutesAgo: 900, isRead: true),
            email("demo-mail-10", from: "Priya Nair", address: "priya.nair@northwind.example",
                  subject: "Notes from the vendor call",
                  preview: "Recap and next steps from this morning's call with the CloudScale team.",
                  minutesAgo: 1500, isRead: true)
        ]
    }

    static var chats: [ChatMessage] {
        [
            // 1:1 chats carry no topic (as Graph reports them), so the row shows
            // the message preview. The group chat keeps its topic.
            ChatMessage(
                chatId: "demo-chat-1", topic: "", from: "Marcus Reid",
                preview: "Did the budget numbers land ok?", sent: ago(6),
                otherParticipants: [], webUrl: "https://teams.microsoft.com/l/chat/demo1"
            ),
            ChatMessage(
                chatId: "demo-chat-2", topic: "Vendor Risk", from: "Priya Nair",
                preview: "Thanks — that unblocks the sign-off.", sent: ago(38),
                otherParticipants: ["Sofia Delgado"], webUrl: "https://teams.microsoft.com/l/chat/demo2"
            ),
            ChatMessage(
                chatId: "demo-chat-3", topic: "", from: "Elena Fischer",
                preview: "Sending the deck in five.", sent: ago(72),
                otherParticipants: [], webUrl: "https://teams.microsoft.com/l/chat/demo3"
            )
        ]
    }

    static var summary: CheckInSummary {
        CheckInSummary(emails: emails, chats: chats, totalUnreadEmails: totalUnreadEmails)
    }

    /// The full body for an opened demo email, so the reader (the iPad detail
    /// pane, or a tapped message) renders real content without a Graph fetch.
    static func emailContent(for id: String) -> EmailContent {
        let body: String
        switch id {
        case "demo-mail-1":
            body = """
            Hi,

            I pushed the revised FY26 model to the shared drive — the licensing line \
            is the one I'd like a second pair of eyes on before Thursday's steering \
            committee. I split the per-seat and enterprise tiers out so we can see \
            where the CloudScale renewal actually lands.

            No rush today, but it would be good to lock the number before Elena \
            finalizes the deck.

            Thanks,
            Marcus
            """
        case "demo-mail-2":
            body = """
            Latest slides attached. I tightened the roadmap section per your notes \
            from Friday and moved the risk register to an appendix so the main flow \
            stays on outcomes.

            Let me know if the framing on slide 6 works for you.

            Elena
            """
        case "demo-mail-3":
            body = """
            Two findings from the SOC 2 review need a response owner before we can \
            sign off:

            1. Access recertification cadence — currently annual, the control calls \
            for quarterly.
            2. Vendor offboarding evidence — we have the process, not the artifacts.

            My suggested owners are inside. Happy to walk through it at the vendor \
            risk session.

            Priya
            """
        default:
            body = """
            Thanks for the note — I'll take a look and get back to you shortly.
            """
        }
        return EmailContent(plainText: body)
    }
}
#endif
