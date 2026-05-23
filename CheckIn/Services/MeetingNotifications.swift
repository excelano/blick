// MeetingNotifications.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UserNotifications
import os

/// Local notifications fired 1 minute before each of today's meetings.
/// Identifiers are prefixed with `checkin.meeting.` so we only remove
/// our own pending requests and leave any unrelated ones (badge auth,
/// etc.) alone. Re-scheduled wholesale on every refresh — Graph's
/// meeting list is the source of truth.
@MainActor
final class MeetingNotifications {
    private let identifierPrefix = "checkin.meeting."
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "notifications")

    /// Prompt for alert + sound permission. Badge is already requested
    /// elsewhere via `updateAppBadge`. Returns the granted state.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Clear any of our pending alerts and re-add one 60 seconds before
    /// each meeting's start. Silently no-ops if the user hasn't granted
    /// alert authorization — the caller (Inbox) gates this on the
    /// `meetingNotifications` AppStorage flag, not on auth state.
    func scheduleAll(_ meetings: [Meeting]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
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
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
