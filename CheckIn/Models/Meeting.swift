// Meeting.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Meeting: Identifiable {
    /// Graph event ID. Needed for the RSVP endpoints (`/me/events/{id}/accept`
    /// etc.) — synthetic UUIDs won't work.
    let id: String
    let subject: String
    let organizer: String
    let start: Date
    /// From `onlineMeeting.joinUrl` when present. iOS routes the URL to
    /// Teams when installed. Nil when the event has no online meeting.
    let joinUrl: String?
    let responseStatus: MeetingResponse

    func with(responseStatus: MeetingResponse) -> Meeting {
        Meeting(id: id,
                subject: subject,
                organizer: organizer,
                start: start,
                joinUrl: joinUrl,
                responseStatus: responseStatus)
    }
}

/// Mirrors Graph's `responseStatus.response` values verbatim.
enum MeetingResponse: String, Codable {
    case none
    case notResponded
    case organizer
    case accepted
    case tentativelyAccepted
    case declined
}
