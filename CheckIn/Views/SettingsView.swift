// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Settings sheet. Sign-out lives here.
struct SettingsView: View {
    var authService: AuthService
    var stateMachine: StateMachine

    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                signOutSection
            }
            .scrollContentBackground(.hidden)
            .background(Brand.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                        .accessibilityLabel("Close settings")
                }
            }
            .confirmationDialog("Sign out of CheckIn?",
                                isPresented: $showSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func signOut() {
        authService.signOut()
        dismiss()
        // Defer so the sheet dismissal animation settles before ContentView
        // swaps SummaryView for SignInView.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            stateMachine.transition(to: .signedOut)
            stateMachine.resetContext()
        }
    }
}

