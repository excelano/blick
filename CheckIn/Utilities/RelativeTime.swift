// RelativeTime.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

func relativeTime(_ date: Date) -> String {
    let seconds = -date.timeIntervalSinceNow

    switch seconds {
    case ..<60:
        return "just now"
    case ..<3600:
        let m = Int(seconds / 60)
        return m == 1 ? "1 min ago" : "\(m) min ago"
    case ..<86400:
        let h = Int(seconds / 3600)
        return h == 1 ? "1 hour ago" : "\(h) hours ago"
    default:
        let d = Int(seconds / 86400)
        return d == 1 ? "yesterday" : "\(d) days ago"
    }
}

func untilTime(_ date: Date) -> String {
    let seconds = date.timeIntervalSinceNow

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

/// True when the meeting starts within the next three minutes (and hasn't
/// started yet). Drives the orange "Starting soon" treatment on the
/// meeting card.
func isMeetingImminent(_ date: Date) -> Bool {
    let seconds = date.timeIntervalSinceNow
    return seconds >= 0 && seconds <= 180
}

private let timeOfDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()

/// Localized time-of-day, no date component (e.g., "2:00 PM" or "14:00"
/// depending on user locale). Used by the "Later today" rows.
func formatTimeOfDay(_ date: Date) -> String {
    timeOfDayFormatter.string(from: date)
}

func truncate(_ s: String, maxLen: Int) -> String {
    let cleaned = s.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: "")
    if cleaned.count <= maxLen {
        return cleaned
    }
    return String(cleaned.prefix(maxLen - 1)) + "\u{2026}"
}
