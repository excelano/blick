// Constants.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import CheckInKit

enum Constants {
    static let redirectURI = "msauth.com.excelano.checkin://auth"

    static let teamsEnabled: Bool = true

    /// Identifier the OS uses for our background refresh task. Must match
    /// the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
    static let backgroundRefreshIdentifier = "com.excelano.checkin.refresh"

    /// Lower bound iOS uses when scheduling our next background run.
    /// Actual run time is at the system's discretion and can be much
    /// later (or never, on a quiet day or after a force-quit).
    static let backgroundRefreshInterval: TimeInterval = 30 * 60

    /// User-supplied client ID if set, otherwise the published default.
    static var effectiveClientID: String {
        let custom = (UserDefaults.standard.string(forKey: AppStorageKey.customClientID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? PublishedConfig.clientID : custom
    }

    /// `https://login.microsoftonline.com/<tenant>` where `<tenant>` is the
    /// user-supplied Directory (tenant) ID, or the published `organizations`
    /// authority when none is set.
    static var effectiveAuthority: String {
        let tenant = (UserDefaults.standard.string(forKey: AppStorageKey.customTenantID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tenant.isEmpty { return PublishedConfig.authority }
        return "https://login.microsoftonline.com/\(tenant)"
    }
}

enum AppStorageKey {
    static let customClientID = "customClientID"
    static let customTenantID = "customTenantID"
    static let showingAllEmails = "showingAllEmails"
    static let meetingNotifications = "meetingNotifications"
}
