// ContentView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Phase 1 placeholder. The auth gate and sign-in view are here so the
// project compiles and you can verify the MSAL flow works end-to-end.
// Phase 2 wires this to the StateMachine; Phase 4 replaces the
// "Signed in." placeholder with SummaryView per D27.

import SwiftUI

struct ContentView: View {
    var authService: AuthService
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        if authService.isAuthenticated {
            placeholderView
        } else {
            signInView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("CheckIn")
                    .font(.system(.largeTitle, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Signed in.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Brand.textMuted)
                Button("Sign Out") {
                    authService.signOut()
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.red)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var signInView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("CheckIn")
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("Sign in with your Microsoft 365 account to get started.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                signIn()
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView().tint(.white)
                    }
                    Text(isSigningIn ? "Signing In..." : "Sign In with Microsoft")
                }
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Brand.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isSigningIn)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                _ = try await authService.signIn(enableTeams: false)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
