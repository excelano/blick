// CheckInWatchWidget.swift
// CheckInWatchWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI
import WidgetKit

/// Timeline entry holding the watch-side snapshot. Nil when the phone
/// hasn't pushed a snapshot yet (fresh install, paired-but-never-synced).
struct WatchStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckInSnapshot?
}

/// Reads the snapshot the `WatchSessionReceiver` last wrote to the watch
/// App Group. No Graph calls, no MSAL — the watch widget extension holds
/// no credentials and never speaks to Microsoft.
struct WatchStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchStatusEntry {
        WatchStatusEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchStatusEntry) -> Void) {
        completion(WatchStatusEntry(date: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchStatusEntry>) -> Void) {
        let snapshot = load()
        let now = Date()
        // Refresh roughly every 15 minutes so the countdown text stays
        // close to live between WatchConnectivity pushes. The receiver
        // calls reloadAllTimelines() on each push, so the system also
        // refreshes whenever fresh data lands.
        let entries = [WatchStatusEntry(date: now, snapshot: snapshot)]
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func load() -> CheckInSnapshot? {
        CheckInSnapshot.loadFromAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
    }
}

// MARK: - Corner

struct WatchCornerView: View {
    let entry: WatchStatusEntry

    var body: some View {
        if let start = entry.snapshot?.nextMeetingStart {
            Image(systemName: "calendar.badge.clock")
                .widgetLabel {
                    Text(untilTime(start, referenceDate: entry.date))
                }
        } else {
            // No upcoming meeting — fall back to a presence dot so the
            // corner still says something useful.
            PresenceGlyph(entry.snapshot?.presence ?? .unknown)
                .widgetLabel {
                    Text(entry.snapshot?.presence.displayName ?? "—")
                }
        }
    }
}

struct CheckInWatchCornerWidget: Widget {
    let kind = "CheckInWatchCorner"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchCornerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryCorner])
        .configurationDisplayName("CheckIn Countdown")
        .description("Time until your next meeting.")
    }
}

// MARK: - Rectangular (Smart Stack)

struct WatchRectangularView: View {
    let entry: WatchStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            presenceLine
            meetingLine
            countsLine
        }
    }

    @ViewBuilder
    private var presenceLine: some View {
        HStack(spacing: 4) {
            if let snapshot = entry.snapshot, snapshot.isOutOfOffice {
                OutOfOfficeGlyph()
                Text("Out of office")
                    .font(.caption2.weight(.semibold))
            } else {
                PresenceGlyph(entry.snapshot?.presence ?? .unknown)
                Text(entry.snapshot?.presence.displayName ?? "—")
                    .font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var meetingLine: some View {
        if let start = entry.snapshot?.nextMeetingStart,
           let subject = entry.snapshot?.nextMeetingSubject {
            HStack(spacing: 4) {
                Text(untilTime(start, referenceDate: entry.date))
                    .foregroundStyle(Brand.accent)
                Text(subject)
                    .lineLimit(1)
            }
            .font(.caption2)
        } else if entry.snapshot != nil {
            Text("No more meetings")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var countsLine: some View {
        if let snapshot = entry.snapshot {
            HStack(spacing: 8) {
                Label("\(snapshot.unreadEmailCount)", systemImage: "envelope.fill")
                Label("\(snapshot.chatCount)", systemImage: "bubble.left.fill")
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .monospacedDigit()
        }
    }
}

struct CheckInWatchRectangularWidget: Widget {
    let kind = "CheckInWatchRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchRectangularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryRectangular])
        .configurationDisplayName("CheckIn Status")
        .description("Presence, next meeting, and counts at a glance.")
    }
}

// MARK: - Circular

struct WatchCircularView: View {
    let entry: WatchStatusEntry

    var body: some View {
        ZStack {
            ringForPresence
            Text(unreadDisplay)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
    }

    private var unreadDisplay: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return "\(snapshot.unreadEmailCount)"
    }

    @ViewBuilder
    private var ringForPresence: some View {
        Circle()
            .stroke(ringColor, lineWidth: 3)
    }

    private var ringColor: Color {
        if let snapshot = entry.snapshot, snapshot.isOutOfOffice { return .purple }
        switch entry.snapshot?.presence ?? .unknown {
        case .available: return .green
        case .busy, .doNotDisturb: return .red
        case .beRightBack, .away: return .yellow
        case .offline: return .gray
        case .unknown: return .gray
        }
    }
}

struct CheckInWatchCircularWidget: Widget {
    let kind = "CheckInWatchCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchCircularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryCircular])
        .configurationDisplayName("CheckIn Unread")
        .description("Unread email count in a presence-colored ring.")
    }
}

// MARK: - Inline

struct WatchInlineView: View {
    let entry: WatchStatusEntry

    var body: some View {
        Text(text)
    }

    private var text: String {
        guard let snapshot = entry.snapshot else { return "CheckIn — waiting" }
        if let start = snapshot.nextMeetingStart {
            return "Next meeting \(untilTime(start, referenceDate: entry.date))"
        }
        if snapshot.unreadEmailCount > 0 {
            return "Inbox: \(snapshot.unreadEmailCount) unread"
        }
        return "All clear today"
    }
}

struct CheckInWatchInlineWidget: Widget {
    let kind = "CheckInWatchInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchInlineView(entry: entry)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryInline])
        .configurationDisplayName("CheckIn Line")
        .description("A one-line CheckIn summary across the top of the face.")
    }
}
