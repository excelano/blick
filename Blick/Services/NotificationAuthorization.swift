// NotificationAuthorization.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import UserNotifications
import os

/// The one alert-permission prompt, shared by meeting reminders and the
/// new-message nudge. Badge-only permission is requested separately by
/// `Inbox.updateAppBadge`; this is the alert + sound upgrade.
enum NotificationAuthorization {
    private static let logger = Logger(subsystem: "com.excelano.checkin", category: "notifications")

    /// Prompt if undecided, otherwise report the current grant. Returns
    /// whether alerts may be shown.
    static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether alerts may be shown right now, without prompting.
    static func isGranted() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
