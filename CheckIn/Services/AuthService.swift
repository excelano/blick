// AuthService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import MSAL
import os

@MainActor @Observable
final class AuthService {
    private(set) var isAuthenticated = false
    private(set) var configurationError: Error?
    private var msalApp: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?
    /// Invoked when the signed-in account is removed so dependent
    /// services (Inbox, GraphClient) can drop their cached user state.
    /// Set by the App layer at construction.
    var onSignOut: (() -> Void)?

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "auth")

    init() {
        configureMSAL()
        checkExistingAccount()
    }

    private func configureMSAL() {
        guard let authorityURL = URL(string: Constants.effectiveAuthority) else {
            configurationError = AuthError.invalidAuthority
            return
        }

        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Constants.effectiveClientID,
                redirectUri: Constants.redirectURI,
                authority: authority
            )
            msalApp = try MSALPublicClientApplication(configuration: config)
            configurationError = nil
        } catch {
            configurationError = error
        }
    }

    /// Rebuild MSAL using the current effective client ID and authority,
    /// after the user changes their custom Azure registration. Signs the
    /// current account out first so the next sign-in goes through the new
    /// registration cleanly. Does not auto-recover any cached account for
    /// the new client ID; the user must re-authenticate.
    func reconfigure() {
        signOut()
        configureMSAL()
    }

    private func checkExistingAccount() {
        guard let msalApp else { return }

        do {
            let accounts = try msalApp.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isAuthenticated = true
            }
        } catch {
            // Silent to the user (falls through to the sign-in
            // screen). Logged for diagnostic visibility.
            logger.error("checkExistingAccount failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signIn(enableTeams: Bool) async throws -> String {
        guard let msalApp else {
            throw configurationError ?? AuthError.notConfigured
        }

        let scopes = Constants.scopes(enableTeams: enableTeams)

        let viewController: UIViewController = try await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let vc = scene.keyWindow?.rootViewController else {
                throw AuthError.noViewController
            }
            return vc
        }

        let webviewParams = MSALWebviewParameters(authPresentationViewController: viewController)
        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webviewParams)

        do {
            let result = try await msalApp.acquireToken(with: params)
            currentAccount = result.account
            isAuthenticated = true
            return result.accessToken
        } catch let error as NSError where Self.isAdminConsentRequired(error) {
            // Chat.ReadWrite triggers admin consent in most tenants. MSAL
            // surfaces this as a serverError with the AADSTS code embedded
            // in the description. Translating to .adminConsentRequired
            // lets SignInView render the curated message in `AuthError`
            // instead of the raw MSAL text.
            throw AuthError.adminConsentRequired
        }
    }

    /// True when the MSAL NSError indicates an admin-consent gap. Matches
    /// on AADSTS codes most strongly tied to consent-required failures and
    /// on the literal word "admin" in the description. Conservative — a
    /// user-cancelled consent (`MSALError.userCanceled` /
    /// `access_denied`) is a different domain code and doesn't trip this.
    private static func isAdminConsentRequired(_ error: NSError) -> Bool {
        guard error.domain == MSALErrorDomain else { return false }
        let description = error.localizedDescription.lowercased()
        return description.contains("aadsts65001")
            || description.contains("aadsts90094")
            || description.contains("admin consent")
            || description.contains("admin approval")
    }

    func acquireTokenSilently(enableTeams: Bool) async throws -> String {
        guard let msalApp, let account = currentAccount else {
            throw AuthError.notAuthenticated
        }

        let scopes = Constants.scopes(enableTeams: enableTeams)
        let params = MSALSilentTokenParameters(scopes: scopes, account: account)

        do {
            let result = try await msalApp.acquireTokenSilent(with: params)
            return result.accessToken
        } catch let error as NSError where error.domain == MSALErrorDomain
            && error.code == MSALError.interactionRequired.rawValue {
            // Token expired and can't refresh silently — need interactive sign-in
            return try await signIn(enableTeams: enableTeams)
        }
    }

    func signOut() {
        guard let msalApp, let account = currentAccount else { return }

        do {
            try msalApp.remove(account)
        } catch {
            // Silent to the user — local state still clears below,
            // so the app behaves as signed out regardless. Logged for
            // diagnostic visibility.
            logger.error("MSAL remove(account) failed during signOut: \(error.localizedDescription, privacy: .public)")
        }

        currentAccount = nil
        isAuthenticated = false
        onSignOut?()
    }
}

enum AuthError: LocalizedError {
    case notConfigured
    case invalidAuthority
    case noViewController
    case notAuthenticated
    case adminConsentRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MSAL is not configured. Check your client ID."
        case .invalidAuthority:
            return "Authority URL is malformed. Check the authority setting."
        case .noViewController:
            return "Could not find a view controller to present sign-in."
        case .notAuthenticated:
            return "No signed-in account. Please sign in first."
        case .adminConsentRequired:
            return "Your organization requires admin consent for Teams access. "
                + "Ask your IT administrator to approve the Chat.ReadWrite permission "
                + "for the CheckIn app. You can still use email and calendar by "
                + "disabling Teams in Settings."
        }
    }
}
