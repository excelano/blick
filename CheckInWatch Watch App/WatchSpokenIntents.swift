// WatchSpokenIntents.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit
import Foundation

/// The watch app's Siri / Shortcuts surface, mirroring the phone's App
/// Intents one-to-one. Siri runs these headless (the app isn't foregrounded),
/// where `WCSession.isReachable` is false, so a live request/reply to the
/// phone isn't possible. Instead:
///
/// - **Reads** answer from the snapshot the phone already pushed (the same
///   one the glance shows). No relay, no reachability, instant — and as
///   fresh as the last push.
/// - **Writes** go over `transferUserInfo`, which is queued and delivered
///   without reachability; the phone runs the actual Graph call when it
///   receives it. The watch speaks an optimistic confirmation, matching the
///   app's optimistic-update pattern.
///
/// All wording comes from `StatusSpeech` (CheckInKit), shared with the phone
/// so the two devices never phrase the same answer differently.

/// Presence options offered to Siri on the watch. Mirrors the phone's
/// `StatusAppEnum`; kept watch-local so the watch needn't link `SharedIntents`.
enum WatchPresenceOption: String, AppEnum {
    case available
    case busy
    case doNotDisturb
    case beRightBack
    case away
    case offline
    case resetToAuto

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Presence"
    static var caseDisplayRepresentations: [WatchPresenceOption: DisplayRepresentation] = [
        .available: "Available",
        .busy: "Busy",
        .doNotDisturb: "Do not disturb",
        .beRightBack: "Be right back",
        .away: "Away",
        .offline: "Offline",
        .resetToAuto: "Reset to auto",
    ]

    var asPresence: Presence {
        switch self {
        case .available: return .available
        case .busy: return .busy
        case .doNotDisturb: return .doNotDisturb
        case .beRightBack: return .beRightBack
        case .away: return .away
        case .offline: return .offline
        case .resetToAuto: return .unknown
        }
    }
}

/// Phrase a read from the last-pushed snapshot, or prompt to sync if the
/// watch has never received one.
@MainActor
private func fromSnapshot(
    _ receiver: WatchSessionReceiver,
    _ build: (CheckInSnapshot) -> String
) -> IntentDialog {
    guard let snapshot = receiver.snapshot else {
        return "Open Blick on your watch to sync with your iPhone first."
    }
    return "\(build(snapshot))"
}

struct WatchSetPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Presence"
    static var description = IntentDescription("Set your Microsoft 365 presence, or reset it to automatic.")
    static var openAppWhenRun = false

    @Parameter(title: "Presence")
    var presence: WatchPresenceOption

    @Dependency var receiver: WatchSessionReceiver

    init() {}
    init(presence: WatchPresenceOption) { self.presence = presence }

    static var parameterSummary: some ParameterSummary {
        Summary("Set my presence to \(\.$presence)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        receiver.sendPresence(presence.asPresence)
        return .result(dialog: "\(StatusSpeech.setPresenceConfirmation(presence.asPresence))")
    }
}

struct WatchCurrentPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Current Presence"
    static var description = IntentDescription("Check your current Microsoft 365 presence.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) {
            StatusSpeech.currentPresence($0.presence, isOutOfOffice: $0.isOutOfOffice)
        })
    }
}

struct WatchNextMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Meeting"
    static var description = IntentDescription("Check your next meeting today.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) { snapshot in
            let meeting = snapshot.currentOrNextMeeting(referenceDate: Date())
            return StatusSpeech.nextMeeting(subject: meeting?.subject, start: meeting?.start)
        })
    }
}

struct WatchSetOutOfOfficeOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On Out of Office"
    static var description = IntentDescription("Turn your Outlook automatic replies on.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        receiver.sendOutOfOffice(true)
        return .result(dialog: "\(StatusSpeech.outOfOfficeConfirmation(true))")
    }
}

struct WatchSetOutOfOfficeOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off Out of Office"
    static var description = IntentDescription("Turn your Outlook automatic replies off.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        receiver.sendOutOfOffice(false)
        return .result(dialog: "\(StatusSpeech.outOfOfficeConfirmation(false))")
    }
}

struct WatchUnreadEmailsIntent: AppIntent {
    static var title: LocalizedStringResource = "Unread Emails"
    static var description = IntentDescription("Count your unread emails.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) {
            StatusSpeech.count($0.unreadEmailCount, singular: "unread email", plural: "unread emails")
        })
    }
}

struct WatchUnreadChatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Unread Chats"
    static var description = IntentDescription("Count your unread chats.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) {
            StatusSpeech.count($0.chatCount, singular: "unread chat", plural: "unread chats")
        })
    }
}

struct WatchRemainingMeetingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Remaining Meetings"
    static var description = IntentDescription("Count your remaining meetings today.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) { snapshot in
            let now = Date()
            let remaining = (snapshot.currentOrNextMeeting(referenceDate: now) != nil ? 1 : 0)
                + snapshot.remainingLaterMeetings(referenceDate: now).count
            return StatusSpeech.remainingMeetings(remaining)
        })
    }
}

struct WatchUnreadMessagesIntent: AppIntent {
    static var title: LocalizedStringResource = "Unread Messages"
    static var description = IntentDescription("Count all your unread messages.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) {
            StatusSpeech.unreadMessages(emails: $0.unreadEmailCount, chats: $0.chatCount)
        })
    }
}

struct WatchWorkdaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Work Day Summary"
    static var description = IntentDescription("Hear your next meeting and unread messages together.")
    static var openAppWhenRun = false

    @Dependency var receiver: WatchSessionReceiver

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: fromSnapshot(receiver) { snapshot in
            let meeting = snapshot.currentOrNextMeeting(referenceDate: Date())
            return StatusSpeech.workdaySummary(
                meetingSubject: meeting?.subject, meetingStart: meeting?.start,
                emails: snapshot.unreadEmailCount, chats: snapshot.chatCount
            )
        })
    }
}

/// Surfaces the watch's intents to Siri with the same spoken phrases as the
/// phone, so they work identically on either device. Every phrase carries the
/// `\(.applicationName)` token the framework requires; since the app name
/// ("Blick") is a real noun it reads naturally — "What's my \(.applicationName)"
/// for the overview, and "in \(.applicationName)" trailing the specific queries.
struct CheckInWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchSetPresenceIntent(),
            phrases: [
                "Set my presence to \(\.$presence) in \(.applicationName)",
                "Change my presence to \(\.$presence) in \(.applicationName)",
                "Mark me as \(\.$presence) in \(.applicationName)",
                "I'm \(\.$presence) in \(.applicationName)",
                "I'm now \(\.$presence) in \(.applicationName)",
                "I'll \(\.$presence) in \(.applicationName)",
                "Go \(\.$presence) in \(.applicationName)",
                "Set my status to \(\.$presence) in \(.applicationName)",
                "Set my status in \(.applicationName)",
                "Change my status in \(.applicationName)",
                "\(\.$presence) in \(.applicationName)",
                "\(\.$presence) me in \(.applicationName)",
            ],
            shortTitle: "Set Presence",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: WatchCurrentPresenceIntent(),
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
            intent: WatchNextMeetingIntent(),
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
            intent: WatchSetOutOfOfficeOnIntent(),
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
            intent: WatchSetOutOfOfficeOffIntent(),
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
            intent: WatchUnreadEmailsIntent(),
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
            intent: WatchUnreadChatsIntent(),
            phrases: [
                "How many unread chats do I have in \(.applicationName)",
                "How many unread chats in \(.applicationName)",
                "Do I have any unread chats in \(.applicationName)",
            ],
            shortTitle: "Unread Chats",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: WatchRemainingMeetingsIntent(),
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
            intent: WatchUnreadMessagesIntent(),
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
            intent: WatchWorkdaySummaryIntent(),
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
