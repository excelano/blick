// WatchSignIn.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AuthenticationServices
import BlickKit
import Foundation
import SwiftUI
import WatchConnectivity

/// Phone side of signing the Apple Watch in on its own. The watch builds the
/// sign-in request and keeps the PKCE verifier; this runs the Microsoft web
/// sign-in and relays only the one-time code back, which the watch redeems for
/// its own token. The phone never sees a token for the watch.
@MainActor @Observable
final class WatchSignIn {
    static let shared = WatchSignIn()

    enum State: Equatable {
        case notSignedIn
        case working
        case signedIn
        case failed(String)
    }

    private(set) var state: State

    private static let callbackScheme = "msauth.\(Bundle.main.bundleIdentifier ?? "com.excelano.checkin").watchkitapp"
    private static let signedInKey = "watchSignedIn"

    private init() {
        state = UserDefaults.standard.bool(forKey: Self.signedInKey) ? .signedIn : .notSignedIn
    }

    var isWatchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    func signIn(using session: WebAuthenticationSession) async {
        state = .working
        do {
            typealias Field = WatchSignInWire.Field
            let began = try await send([
                WatchSignInWire.stepKey: WatchSignInWire.Step.begin,
                Field.clientID: Constants.effectiveClientID,
                Field.authority: Constants.effectiveAuthority,
            ])
            guard let urlString = began[Field.url] as? String, let url = URL(string: urlString) else {
                throw WatchSignInError.message("The watch did not answer. Open Blick on the watch and try again.")
            }
            let callback = try await session.authenticate(using: url, callbackURLScheme: Self.callbackScheme)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if let error = value("error") {
                throw WatchSignInError.message(value("error_description") ?? error)
            }
            guard let code = value(Field.code), let state = value(Field.state) else {
                throw WatchSignInError.message("Microsoft returned no sign-in code.")
            }
            WCSession.default.transferUserInfo([
                WatchSignInWire.stepKey: WatchSignInWire.Step.code,
                Field.code: code,
                Field.state: state,
            ])
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            state = persistedState
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([WatchSignInWire.stepKey: WatchSignInWire.Step.signOut])
        setSignedIn(false)
    }

    func handleReport(_ result: String) {
        if result == WatchSignInWire.Report.signedIn {
            setSignedIn(true)
        } else if result == WatchSignInWire.Report.signedOut {
            setSignedIn(false)
        } else if result.hasPrefix(WatchSignInWire.Report.failedPrefix) {
            state = .failed(String(result.dropFirst(WatchSignInWire.Report.failedPrefix.count)))
        }
    }

    private var persistedState: State {
        UserDefaults.standard.bool(forKey: Self.signedInKey) ? .signedIn : .notSignedIn
    }

    private func setSignedIn(_ signedIn: Bool) {
        UserDefaults.standard.set(signedIn, forKey: Self.signedInKey)
        state = signedIn ? .signedIn : .notSignedIn
    }

    private func send(_ message: [String: Any]) async throws -> [String: Any] {
        let session = WCSession.default
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !(session.activationState == .activated && session.isReachable) {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else {
            throw WatchSignInError.message("The watch is not reachable. Wake it and open Blick on it, then try again.")
        }
        nonisolated(unsafe) let message = message
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { continuation.resume(returning: $0) },
                errorHandler: { continuation.resume(throwing: $0) }
            )
        }
    }
}

private enum WatchSignInError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}
