// DemoMode.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Demo/screenshot mode, shared by the app, the widget, and the watch so all
// three surfaces agree on when to show sample data instead of a real account.
// DEBUG-only: the flag reads false in release and the sample data (DemoData in
// the app, DemoSnapshot here) is compiled out. Toggled by the `--demo` launch
// argument (for automated simulator capture) or the "Demo mode" switch in the
// app's Settings.

import Foundation

public enum DemoMode {
    /// The UserDefaults key the Settings toggle writes and this flag reads.
    public static let userDefaultsKey = "demoMode"

    public static var isActive: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") { return true }
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
        #else
        return false
        #endif
    }

    /// Whether to open the full email list on launch, for capturing that screen
    /// without a tap. Set by the `--demo-email-list` launch argument alongside
    /// `--demo`. Release always returns false.
    public static var opensEmailList: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--demo-email-list")
        #else
        return false
        #endif
    }
}
