// MeetingContextMenu.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UIKit

/// The long-press menu shared by every meeting row: the summary's meeting
/// card and "Later today" rows, and the agenda screen's rows. Lives here
/// rather than on one screen so the two can't drift — the agenda is where
/// an unanswered invite for next week actually shows up, so it needs the
/// same RSVP actions the summary has always had.
///
/// `onResolveConflict` is a closure rather than a sheet presented here,
/// because each screen owns its own `conflictTarget` state and presents
/// `ConflictResolutionSheet` itself.
@MainActor
@ViewBuilder
func meetingContextMenu(for meeting: Meeting,
                        inbox: Inbox,
                        onResolveConflict: @escaping (Meeting) -> Void) -> some View {
    if meeting.hasConflict {
        Button {
            onResolveConflict(meeting)
        } label: {
            Label("Resolve conflict", systemImage: "exclamationmark.triangle")
        }
        Divider()
    }
    if meeting.responseStatus.canRsvp {
        if meeting.responseStatus != .accepted {
            Button {
                Task { await inbox.respondToMeeting(.accepted, meetingId: meeting.id) }
            } label: {
                Label("Accept", systemImage: "checkmark")
            }
        }
        if meeting.responseStatus != .tentativelyAccepted {
            Button {
                Task { await inbox.respondToMeeting(.tentativelyAccepted, meetingId: meeting.id) }
            } label: {
                Label("Tentative", systemImage: "questionmark")
            }
        }
        if meeting.responseStatus != .declined {
            Button(role: .destructive) {
                Task { await inbox.respondToMeeting(.declined, meetingId: meeting.id) }
            } label: {
                Label("Decline", systemImage: "xmark")
            }
        }
        Divider()
    }
    if let urlString = meeting.joinUrl {
        Button {
            UIPasteboard.general.string = urlString
        } label: {
            Label("Copy join link", systemImage: "doc.on.doc")
        }
    }
    if meeting.responseStatus.canRsvp,
       let email = meeting.organizerEmail, !email.isEmpty {
        Button {
            UIPasteboard.general.string = email
        } label: {
            Label("Copy organizer email", systemImage: "doc.on.doc")
        }
    }
    // Delete is hidden when Decline is already available — they
    // functionally do the same thing from the user's perspective
    // (get the meeting off the day's view). Decline is shown
    // whenever the user can RSVP and hasn't already declined.
    let canDecline = meeting.responseStatus.canRsvp && meeting.responseStatus != .declined
    if !canDecline {
        Divider()
        Button(role: .destructive) {
            Task { await inbox.deleteMeeting(meetingId: meeting.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
