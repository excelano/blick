// WatchSignInRelay.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickKit
import Foundation
import WatchConnectivity

/// Watch side of signing in: answers the phone's `begin` with an authorize
/// URL, then redeems the one-time code the phone relays back. The verifier
/// stays here, so the phone never holds anything that could be redeemed.
@MainActor
final class WatchSignInRelay {
    static let shared = WatchSignInRelay()

    private var pending: WatchSignInAttempt?

    func handle(_ message: [String: Any]) async -> [String: Any] {
        typealias Field = WatchSignInWire.Field
        switch message[WatchSignInWire.stepKey] as? String {
        case WatchSignInWire.Step.begin:
            let registration = WatchRegistration(
                clientID: message[Field.clientID] as? String ?? PublishedConfig.clientID,
                authority: message[Field.authority] as? String ?? PublishedConfig.authority
            )
            let attempt = WatchSignInAttempt(registration: registration)
            pending = attempt
            return [Field.url: attempt.authorizeURL.absoluteString]
        case WatchSignInWire.Step.code:
            guard let attempt = pending, message[Field.state] as? String == attempt.state,
                  let code = message[Field.code] as? String else {
                Self.sendReport("\(WatchSignInWire.Report.failedPrefix)the sign-in did not match")
                return [:]
            }
            pending = nil
            do {
                try await WatchTokenProvider.shared.completeSignIn(attempt, code: code)
                Self.sendReport(WatchSignInWire.Report.signedIn)
            } catch {
                Self.sendReport("\(WatchSignInWire.Report.failedPrefix)\(error.localizedDescription)")
            }
            return [:]
        case WatchSignInWire.Step.signOut:
            await WatchTokenProvider.shared.signOut()
            Self.sendReport(WatchSignInWire.Report.signedOut)
            return [:]
        default:
            return [:]
        }
    }

    nonisolated static func sendReport(_ result: String) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([WatchSignInWire.reportKey: result])
    }
}
