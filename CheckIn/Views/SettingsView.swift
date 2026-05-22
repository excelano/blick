// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SettingsView: View {
    var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Brand.bgDarker)
                }
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

    private func signOut() {
        dismiss()
        // Let the sheet dismissal animate before the parent view swaps;
        // otherwise the cross-fade looks chopped.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            authService.signOut()
        }
    }
}
