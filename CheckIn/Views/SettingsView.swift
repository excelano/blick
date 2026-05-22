// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SettingsView: View {
    var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    @AppStorage(AppStorageKey.customClientID) private var storedClientID: String = ""
    @AppStorage(AppStorageKey.customTenantID) private var storedTenantID: String = ""

    /// Edits go into the draft fields; they only land in `@AppStorage` when
    /// the user taps Save or Reset, so dismissing without saving discards.
    @State private var draftClientID: String = ""
    @State private var draftTenantID: String = ""

    var body: some View {
        NavigationStack {
            Form {
                advancedSection
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
            .onAppear {
                draftClientID = storedClientID
                draftTenantID = storedTenantID
            }
        }
        .preferredColorScheme(.dark)
    }

    private var advancedSection: some View {
        Section {
            TextField("Application (client) ID", text: $draftClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(.body, design: .monospaced))
                .listRowBackground(Brand.bgDarker)
            TextField("Directory (tenant) ID", text: $draftTenantID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(.body, design: .monospaced))
                .listRowBackground(Brand.bgDarker)
            Button("Save and sign in") {
                save()
            }
            .foregroundStyle(Brand.accent)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Brand.bgDarker)
            Button("Reset to defaults", role: .destructive) {
                resetToDefaults()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Brand.bgDarker)
        } header: {
            Text("Custom Azure registration")
        } footer: {
            Text("Leave both blank to use Excelano's published registration. Leave the tenant ID blank to sign in against any tenant. Your registration must accept msauth.com.excelano.checkin://auth as a redirect URI.")
        }
    }

    private var signOutSection: some View {
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

    private func save() {
        storedClientID = draftClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        storedTenantID = draftTenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        authService.reconfigure()
        dismiss()
    }

    private func resetToDefaults() {
        draftClientID = ""
        draftTenantID = ""
        storedClientID = ""
        storedTenantID = ""
        authService.reconfigure()
        dismiss()
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
