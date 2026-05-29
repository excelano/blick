// RelativeTime.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Format the gap from `referenceDate` to a future `date` as a human
/// phrase: "now", "Starting soon", "in N min", "in N hour(s)", "in Nh Mm".
/// The widget passes the timeline entry's date so the countdown stays
/// correct across pre-generated entries; the in-app surface passes
/// `.now` and re-renders periodically.
public func untilTime(_ date: Date, referenceDate: Date) -> String {
    let seconds = date.timeIntervalSince(referenceDate)

    if seconds < 0 {
        return "now"
    }
    if seconds <= 180 {
        return "Starting soon"
    }

    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours == 0 {
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }
    if minutes == 0 {
        return hours == 1 ? "in 1 hour" : "in \(hours) hours"
    }
    return "in \(hours)h \(minutes)m"
}

/// True when the meeting starts within the next three minutes of
/// `referenceDate` (and hasn't started yet). Drives the orange
/// "Starting soon" treatment on the meeting card and widget pill.
public func isMeetingImminent(_ date: Date, referenceDate: Date) -> Bool {
    let seconds = date.timeIntervalSince(referenceDate)
    return seconds >= 0 && seconds <= 180
}
