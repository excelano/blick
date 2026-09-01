// AgendaView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The full agenda screen, reached by tapping the summary's "Later today"
/// header. Shows a rolling window of `Inbox.agendaDayCount` days starting
/// at the top of today, grouped under day headers, so "what does tomorrow
/// look like" is one tap rather than a trip to the Calendar app.
///
/// A rolling list rather than a day-at-a-time pager: the question this
/// screen answers is "what's coming up," and a pager charges a tap per day
/// to answer it.
///
/// Meetings come from `Inbox`'s shared store, not from local state, so an
/// RSVP or delete performed from the conflict sheet is reflected here
/// immediately and the conflict triangles stay consistent with the
/// summary's.
struct AgendaView: View {
    var inbox: Inbox
    let onClose: () -> Void

    @State private var loaded = false
    @State private var failed = false
    /// The meeting whose conflict the user wants to resolve, driving the
    /// same sheet the summary uses.
    @State private var conflictTarget: Meeting?
    /// Reference clock for the past/live split, advanced every 30 seconds
    /// so a meeting crosses from upcoming to live to past without a
    /// refresh — the same cadence the summary's `clockTick` uses.
    @State private var clockTick: Date = .now

    var body: some View {
        NavigationStack {
            BrowseListContent(
                items: days,
                isLoading: !loaded,
                failed: failed,
                failedText: "Couldn't load your calendar. Check your connection and try again.",
                emptyText: "Nothing scheduled in the next \(Inbox.agendaDayCount) days."
            ) { agendaList($0) }
                .browseListChrome(title: "Agenda", onClose: onClose)
        }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                clockTick = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $conflictTarget) { target in
            ConflictResolutionSheet(inbox: inbox, primaryMeetingId: target.id)
        }
    }

    /// The agenda grouped into calendar days, each with its meetings in
    /// start order. Days with nothing scheduled are omitted rather than
    /// rendered empty — a week with two free days should be short, not
    /// padded with blanks.
    private var days: [AgendaDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: inbox.agendaMeetings) {
            calendar.startOfDay(for: $0.start)
        }
        return grouped.keys.sorted().map { day in
            AgendaDay(date: day, meetings: grouped[day, default: []].sorted { $0.start < $1.start })
        }
    }

    private func agendaList(_ days: [AgendaDay]) -> some View {
        List {
            ForEach(days) { day in
                Section {
                    ForEach(day.meetings) { meeting in
                        LaterMeetingRow(
                            meeting: meeting,
                            onTap: { openMeetingInTeams(joinUrl: meeting.joinUrl) },
                            onConflictTap: { conflictTarget = meeting },
                            isPast: meeting.end <= clockTick
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
    }

    private func dayHeader(_ day: AgendaDay) -> some View {
        HStack(spacing: 8) {
            Text(day.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.textMuted)
                .textCase(.uppercase)
            Text("\(day.meetings.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(Brand.bgDarker)
                .clipShape(Capsule())
            Spacer(minLength: 0)
        }
        .transaction { $0.animation = nil }
    }

    private func load() async {
        do {
            try await inbox.refreshAgenda()
            loaded = true
        } catch {
            failed = true
        }
    }
}

/// One calendar day's worth of the agenda. Identified by the day itself,
/// so SwiftUI keeps row identity stable as the window rolls forward.
struct AgendaDay: Identifiable {
    let date: Date
    let meetings: [Meeting]

    var id: Date { date }

    /// "Today" and "Tomorrow" for the near days, then a weekday-and-date
    /// form ("Thursday, Sep 4") that stays unambiguous across the week.
    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
