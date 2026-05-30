// CheckInWatchApp.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

@main
struct CheckInWatchApp: App {
    @State private var receiver = WatchSessionReceiver()

    var body: some Scene {
        WindowGroup {
            WatchGlanceView(receiver: receiver)
        }
    }
}
