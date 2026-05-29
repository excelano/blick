// WidgetTokenProvider.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInGraph
import CheckInKit
import Foundation
import MSAL

/// Supplies a Graph token to `GraphCore` from inside the widget extension.
/// On iOS 18+ an interactive-widget intent runs in the extension, not the app,
/// so the extension acquires its own token silently from the shared MSAL
/// keychain cache. The token never leaves the device — this is the same cache
/// the app filled when the user signed in there.
///
/// MSAL caches the access token until expiry, so each `graphAccessToken()`
/// call hits that cache rather than the network. Holding no mutable state
/// ourselves keeps the provider trivially Sendable.
final class WidgetTokenProvider: GraphTokenProvider {
    func graphAccessToken() async throws -> String {
        let config = widgetEffectiveConfig()
        guard let authorityURL = URL(string: config.authority) else {
            throw WidgetTokenError.notConfigured
        }
        let authority = try MSALAADAuthority(url: authorityURL)
        // redirectUri nil → MSAL derives the extension's own default,
        // msauth.com.excelano.checkin.CheckInWidget://auth. MSAL locks that
        // msauth.<bundle_id> format to the running bundle, so the extension
        // can't reuse the app's URI; its own must be registered in Entra or
        // silent token refresh fails (AADSTS50011). Pin the shared cache group.
        let msalConfig = MSALPublicClientApplicationConfig(
            clientId: config.clientID,
            redirectUri: nil,
            authority: authority
        )
        msalConfig.cacheConfig.keychainSharingGroup = "com.microsoft.adalcache"
        let app = try MSALPublicClientApplication(configuration: msalConfig)
        guard let account = try app.allAccounts().first else {
            throw WidgetTokenError.notAuthenticated
        }
        let params = MSALSilentTokenParameters(scopes: GraphScopes.all, account: account)
        return try await app.acquireTokenSilent(with: params).accessToken
    }
}

enum WidgetTokenError: Error {
    case notConfigured
    case notAuthenticated
}

/// The MSAL config the widget needs to match the app's, read from the App
/// Group the app writes. Falls back to the published defaults when the app
/// hasn't written a custom (self-hosted) Azure registration. Shared by the
/// token provider and the status-action session heartbeat.
func widgetEffectiveConfig() -> (clientID: String, authority: String) {
    let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier)
    let clientID = defaults?.string(forKey: CheckInSnapshot.effectiveClientIDKey)
        ?? PublishedConfig.clientID
    let authority = defaults?.string(forKey: CheckInSnapshot.effectiveAuthorityKey)
        ?? PublishedConfig.authority
    return (clientID, authority)
}
