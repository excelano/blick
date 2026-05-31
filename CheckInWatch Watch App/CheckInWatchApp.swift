// CheckInWatchApp.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import SwiftUI

@main
struct CheckInWatchApp: App {
    @State private var receiver: WatchSessionReceiver

    init() {
        // One receiver instance backs both the glance and the relay
        // intents. Register it so the watch's App Intents resolve the same
        // live WCSession link Siri needs to reach the phone; the system
        // runs this init before any intent's perform().
        let receiver = WatchSessionReceiver()
        AppDependencyManager.shared.add(dependency: receiver)
        _receiver = State(initialValue: receiver)
    }

    var body: some Scene {
        WindowGroup {
            WatchGlanceView(receiver: receiver)
        }
    }
}
