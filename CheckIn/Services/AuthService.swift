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

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "auth")

    init() {
        configureMSAL()
        checkExistingAccount()
    }

    // MARK: - Configuration

    private func configureMSAL() {
        guard let authorityURL = URL(string: Constants.authority) else {
            configurationError = AuthError.invalidAuthority
            return
        }

        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Constants.clientID,
                redirectUri: Constants.redirectURI,
                authority: authority
            )
            msalApp = try MSALPublicClientApplication(configuration: config)
        } catch {
            configurationError = error
        }
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
            // Silent to the user per D24 (falls through to the sign-in
            // screen). Logged for diagnostic visibility.
            logger.error("checkExistingAccount failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sign In (interactive browser flow)

    func signIn(enableTeams: Bool) async throws -> String {
        guard let msalApp else {
            throw configurationError ?? AuthError.notConfigured
        }

        let scopes = Constants.scopes(enableTeams: enableTeams)

        // Get the root view controller for presenting the auth browser
        let viewController: UIViewController = try await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let vc = scene.keyWindow?.rootViewController else {
                throw AuthError.noViewController
            }
            return vc
        }

        let webviewParams = MSALWebviewParameters(authPresentationViewController: viewController)
        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webviewParams)

        let result = try await msalApp.acquireToken(with: params)
        currentAccount = result.account
        isAuthenticated = true
        return result.accessToken
    }

    // MARK: - Silent Token Refresh

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

    // MARK: - Sign Out

    func signOut() {
        guard let msalApp, let account = currentAccount else { return }

        do {
            try msalApp.remove(account)
        } catch {
            // Silent to the user per D24 — local state still clears below,
            // so the app behaves as signed out regardless. Logged for
            // diagnostic visibility.
            logger.error("MSAL remove(account) failed during signOut: \(error.localizedDescription, privacy: .public)")
        }

        currentAccount = nil
        isAuthenticated = false
    }
}

// MARK: - Errors

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
