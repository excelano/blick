// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import MSAL

@main
struct CheckInApp: App {
    @State private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService)
                .onOpenURL { url in
                    // Pass the MSAL redirect callback URL back to MSAL
                    MSALPublicClientApplication.handleMSALResponse(
                        url, sourceApplication: nil
                    )
                }
        }
    }
}
