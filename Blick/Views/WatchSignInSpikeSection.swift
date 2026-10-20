// WatchSignInSpikeSection.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if DEBUG
import AuthenticationServices
import SwiftUI
import WatchConnectivity

struct WatchSignInSpikeSection: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var lines: [String] = []
    @State private var working = false

    private static let callbackScheme = "msauth.com.excelano.checkin.watchkitapp"

    var body: some View {
        Section {
            Button("Sign in the watch") {
                working = true
                Task {
                    do { try await signInWatch() } catch { lines.append("FAILED: \(error.localizedDescription)") }
                    working = false
                }
            }
            .disabled(working)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption)
            }
        } header: {
            Text("Tier 2 spike")
        } footer: {
            Text("The watch builds the sign-in request, this phone runs the Microsoft sign-in and relays the one-time code back, and the watch redeems it itself.")
        }
    }

    private func signInWatch() async throws {
        lines = ["asking the watch to begin"]
        let began = try await send(["spike": "begin"])
        guard let urlString = began["url"] as? String, let url = URL(string: urlString) else {
            throw SpikeRelayError.message("watch sent no sign-in URL")
        }
        let callback = try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: Self.callbackScheme
        )
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw SpikeRelayError.message("\(error): \(value("error_description") ?? "")")
        }
        guard let code = value("code"), let state = value("state") else {
            throw SpikeRelayError.message("callback had no code")
        }
        lines.append("got code, queued for the watch; its screen shows the result")
        WCSession.default.transferUserInfo(["spike": "code", "code": code, "state": state])
    }

    private func send(_ message: [String: Any]) async throws -> [String: Any] {
        let session = WCSession.default
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !(session.activationState == .activated && session.isReachable) {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, session.isReachable else {
            throw SpikeRelayError.message("watch not reachable; open the Blick watch app")
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { continuation.resume(returning: $0) },
                errorHandler: { continuation.resume(throwing: $0) }
            )
        }
    }
}

private enum SpikeRelayError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): String(text.prefix(300))
        }
    }
}
#endif
