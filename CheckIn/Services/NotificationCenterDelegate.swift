// NotificationCenterDelegate.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import UIKit
import UserNotifications

/// Routes meeting-notification taps to the same place tapping a
/// meeting card would: the Teams join URL if there is one, otherwise
/// Outlook's calendar. Also lets alerts surface as banners while the
/// app is foregrounded.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let joinUrl = response.notification.request.content.userInfo["joinUrl"] as? String
        Task { @MainActor in
            await openMeeting(joinUrlString: joinUrl)
            completionHandler()
        }
    }

    @MainActor
    private func openMeeting(joinUrlString: String?) async {
        if let urlString = joinUrlString,
           let url = DeepLinkService.passthrough(urlString),
           UIApplication.shared.canOpenURL(url) {
            let ok = await UIApplication.shared.open(url)
            if ok { return }
        }
        if let url = DeepLinkService.outlookCalendar,
           UIApplication.shared.canOpenURL(url) {
            _ = await UIApplication.shared.open(url)
        }
    }
}
