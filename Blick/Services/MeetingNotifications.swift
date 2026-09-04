// MeetingNotifications.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UserNotifications
import os

/// Local notifications fired 1 minute before each of today's meetings.
/// Identifiers are prefixed with `blick.meeting.` so we only remove
/// our own pending requests and leave any unrelated ones (badge auth,
/// etc.) alone. Re-scheduled wholesale on every refresh — Graph's
/// meeting list is the source of truth.
@MainActor
final class MeetingNotifications {
    private let identifierPrefix = "blick.meeting."

    /// Prefixes earlier builds scheduled under. A pending notification lives
    /// in iOS's store, not in the app, so a build that renames its prefix can
    /// no longer match — and therefore never cancels — what a previous build
    /// left on the schedule. The CheckIn-to-Blick rename did exactly that, and
    /// every meeting already scheduled fired twice: once from the stale
    /// `checkin.meeting.` request and once from its `blick.meeting.`
    /// replacement. `clearAll` sweeps every prefix the app has ever used.
    /// Add to this list rather than editing `identifierPrefix` in place.
    private let legacyIdentifierPrefixes = ["checkin.meeting."]

    private var allIdentifierPrefixes: [String] {
        [identifierPrefix] + legacyIdentifierPrefixes
    }
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "notifications")

    /// Clear any of our pending alerts and re-add one 60 seconds before
    /// each meeting's start. Silently no-ops if the user hasn't granted
    /// alert authorization — the caller (Inbox) gates this on the
    /// `meetingNotifications` AppStorage flag, not on auth state.
    func scheduleAll(_ meetings: [Meeting]) async {
        let center = UNUserNotificationCenter.current()
        guard await NotificationAuthorization.isGranted() else {
            await clearAll()
            return
        }
        await clearAll()

        let now = Date()
        for meeting in meetings {
            let fireDate = meeting.start.addingTimeInterval(-60)
            if fireDate <= now { continue }

            let content = UNMutableNotificationContent()
            content.title = meeting.subject
            content.body = "Starts in 1 minute"
            content.sound = .default
            if let joinUrl = meeting.joinUrl {
                content.userInfo["joinUrl"] = joinUrl
            }

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + meeting.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("schedule failed for \(meeting.subject, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { id in
            allIdentifierPrefixes.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
