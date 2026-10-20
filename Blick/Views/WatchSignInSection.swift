// WatchSignInSection.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AuthenticationServices
import BlickKit
import SwiftUI

/// Settings section for signing the Apple Watch in on its own, so it can fetch
/// from Microsoft Graph when the iPhone is away. Off until the user signs the
/// watch in; shown only when a watch with Blick installed is paired.
struct WatchSignInSection: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    private let watchSignIn = WatchSignIn.shared

    var body: some View {
        if watchSignIn.isWatchAvailable {
            Section {
                switch watchSignIn.state {
                case .signedIn:
                    Label("Signed in on Apple Watch", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Brand.textMuted)
                    Button("Remove from Apple Watch", role: .destructive) { watchSignIn.signOut() }
                case .working:
                    HStack {
                        Text("Signing in the watch")
                        Spacer()
                        ProgressView()
                    }
                case .notSignedIn:
                    signInButton
                case .failed(let message):
                    signInButton
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Signs the watch in on its own so it can refresh and act when your iPhone is away. This iPhone runs the Microsoft sign-in and passes the watch a one-time code. The watch exchanges it for its own token, which stays on the watch.")
            }
            .listRowBackground(Brand.bgDarker)
        }
    }

    private var signInButton: some View {
        Button("Sign in on Apple Watch") {
            Task { await watchSignIn.signIn(using: webAuthenticationSession) }
        }
    }
}
