// GraphFilters.swift
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// Shared predicates over Graph results, kept in one place so the in-app code
// (`GraphClient`) and the widget/watch snapshot code (`GraphCore`) can never
// disagree on what counts as an unread chat or an attendable meeting. The two
// decode the same JSON into different structs, so these operate on the
// extracted fields rather than a shared type.

/// Whether a chat has unread activity worth surfacing: not hidden in Teams, a
/// real user message (not a join/leave/rename system event), and a last
/// message newer than the user's last-read mark. There is no age cutoff — an
/// unread chat counts however old its last message is.
public func isUnreadChat(
    isHidden: Bool?,
    messageType: String,
    hasSenderUser: Bool,
    sent: Date?,
    lastRead: Date?
) -> Bool {
    if isHidden == true { return false }
    // Keep regular messages (and the rare empty-string messageType); drop
    // everything else — joins, leaves, renames, etc.
    guard messageType.isEmpty || messageType == "message" else { return false }
    guard hasSenderUser, let sent else { return false }
    // `lastRead` is nil for chats never opened; .distantPast makes any real
    // message read as unread, matching Graph's "0001-01-01" sentinel.
    return sent > (lastRead ?? .distantPast)
}

/// Whether a calendar event should be shown or counted: not cancelled (Graph
/// keeps cancelled events in calendarView until removed) and not declined
/// (some tenants keep declined invites on the calendar). Applied client-side
/// because calendarView's `$filter` support for these fields is narrow.
public func isAttendableMeeting(isCancelled: Bool?, response: String?) -> Bool {
    !(isCancelled ?? false) && response != "declined"
}

/// The `[now, start-of-tomorrow-local)` window CheckIn uses for "today's
/// remaining meetings", so neither the app nor the snapshot bleeds into
/// tomorrow's calendar.
public func todayMeetingWindow(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    return (now, end)
}
