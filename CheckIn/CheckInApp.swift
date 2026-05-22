// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import MSAL

@main
struct CheckInApp: App {
    @State private var authService: AuthService
    private let inbox: Inbox

    init() {
        let auth = AuthService()
        let graph = GraphClient(authService: auth, enableTeams: Constants.teamsEnabled)
        _authService = State(initialValue: auth)
        self.inbox = Inbox(graphClient: graph, teamsEnabled: Constants.teamsEnabled)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService, inbox: inbox)
                .onOpenURL { url in
                    MSALPublicClientApplication.handleMSALResponse(
                        url, sourceApplication: nil
                    )
                }
        }
    }
}
