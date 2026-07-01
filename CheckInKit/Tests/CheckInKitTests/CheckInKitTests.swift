// CheckInKitTests.swift
// CheckInKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import CheckInKit

/// Records the values forwarded through a `StatusActions` box.
@MainActor
final class StatusRecorder {
    var appliedPresence: Presence?
    var appliedOutOfOffice: Bool?
}

@MainActor
struct StatusActionsTests {
    /// `StatusActions` forwards each call to the handler the app wired in.
    /// (The intents' `@Dependency` resolution can't be unit-tested —
    /// `@Dependency` is injected only when the system runs an intent, not
    /// when `perform()` is called directly — so that path is verified
    /// on-device via Siri / the widget instead.)
    @Test func statusActionsForwardToHandlers() async throws {
        let recorder = StatusRecorder()
        let actions = StatusActions(
            presence: { recorder.appliedPresence = $0 },
            outOfOffice: { recorder.appliedOutOfOffice = $0 }
        )

        try await actions.applyPresence(.busy)
        try await actions.applyOutOfOffice(true)

        #expect(recorder.appliedPresence == .busy)
        #expect(recorder.appliedOutOfOffice == true)
    }
}

struct ReadAloudTests {
    /// Chats read before emails; each medium labels itself; the queue is not
    /// capped when it fits, so no overflow tail.
    @Test func ordersChatsThenEmailsWithNoOverflow() {
        let (lines, overflow) = StatusSpeech.readAloud(
            chats: [("Bob", "Are you joining standup?"), ("Priya", "Pushed the fix")],
            chatTotal: 2,
            emails: [("Sarah", "Q3 budget", "Look before Friday")],
            emailTotal: 1
        )
        #expect(lines == [
            "Teams from Bob: Are you joining standup.",
            "Teams from Priya: Pushed the fix.",
            "Email from Sarah, Q3 budget: Look before Friday."
        ])
        #expect(overflow == nil)
    }

    /// The cap fills with chats first, then as many emails as fit, and the tail
    /// counts everything past the cap from the true totals.
    @Test func capsAtFiveAndReportsOverflow() {
        let (lines, overflow) = StatusSpeech.readAloud(
            chats: [("A", "one"), ("B", "two"), ("C", "three")],
            chatTotal: 3,
            emails: [("D", "s", "four"), ("E", "s", "five"), ("F", "s", "six"), ("G", "s", "seven")],
            emailTotal: 4
        )
        #expect(lines.count == StatusSpeech.readAloudCap)
        #expect(overflow == "And 2 more emails unread.")
    }

    /// `emailTotal` is the server-side unread count, which can exceed the
    /// sampled array — the overflow reflects the total, not the sample.
    @Test func overflowUsesServerTotalNotSampleSize() {
        let (_, overflow) = StatusSpeech.readAloud(
            chats: [("A", "one"), ("B", "two")],
            chatTotal: 2,
            emails: [("C", "s", "x"), ("D", "s", "y"), ("E", "s", "z")],
            emailTotal: 30
        )
        // 2 chats + 3 emails read (cap 5); 30 - 3 = 27 emails still unread.
        #expect(overflow == "And 27 more emails unread.")
    }

    @Test func singularOverflowGrammar() {
        let (_, overflow) = StatusSpeech.readAloud(
            chats: [], chatTotal: 0,
            emails: [("A", "s", "x")], emailTotal: 2
        )
        #expect(overflow == "And 1 more email unread.")
    }

    @Test func emptyInboxHasNoLinesOrOverflow() {
        let (lines, overflow) = StatusSpeech.readAloud(
            chats: [], chatTotal: 0, emails: [], emailTotal: 0
        )
        #expect(lines.isEmpty)
        #expect(overflow == nil)
    }

    @Test func emptySenderFallsBackToSomeone() {
        let (lines, _) = StatusSpeech.readAloud(
            chats: [("   ", "hi there")], chatTotal: 1, emails: [], emailTotal: 0
        )
        #expect(lines == ["Teams from someone: hi there."])
    }

    @Test func emptySubjectDropsTheComma() {
        let (lines, _) = StatusSpeech.readAloud(
            chats: [], chatTotal: 0,
            emails: [("Bob", "", "quick question")], emailTotal: 1
        )
        #expect(lines == ["Email from Bob: quick question."])
    }

    @Test func emptyPreviewYieldsBareLine() {
        let (lines, _) = StatusSpeech.readAloud(
            chats: [("Bob", "")], chatTotal: 1, emails: [], emailTotal: 0
        )
        #expect(lines == ["Teams from Bob."])
    }

    /// Long previews trim at a word boundary within the limit, carry no
    /// ellipsis, and still end in the line's own period.
    @Test func longPreviewTrimsAtWordBoundary() {
        let long = String(repeating: "alpha ", count: 50) // 300 chars
        let (lines, _) = StatusSpeech.readAloud(
            chats: [("Bob", long)], chatTotal: 1, emails: [], emailTotal: 0
        )
        let line = try! #require(lines.first)
        #expect(line.hasPrefix("Teams from Bob: alpha"))
        #expect(line.hasSuffix("."))
        #expect(!line.contains("…"))
        #expect(!line.contains("  ")) // whitespace collapsed
        #expect(line.count < 190)     // snippet bounded by the 160-char cap
    }
}

struct CheckInSnapshotTests {
    private static let sample = CheckInSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        nextMeetingSubject: "Status sync",
        nextMeetingStart: Date(timeIntervalSince1970: 1_700_001_000),
        nextMeetingEnd: Date(timeIntervalSince1970: 1_700_002_800),
        nextMeetingOrganizer: "David",
        nextMeetingJoinUrl: "https://teams.microsoft.com/l/meetup-join/preview",
        unreadEmailCount: 7,
        chatCount: 3,
        presence: .busy,
        isOutOfOffice: true
    )

    /// Encode + decode preserves every field, including the `Presence` enum
    /// (which only round-trips because we conformed it to `Codable` when
    /// adding it to the snapshot).
    @Test func snapshotRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let decoded = try JSONDecoder().decode(CheckInSnapshot.self, from: data)

        #expect(decoded.updatedAt == Self.sample.updatedAt)
        #expect(decoded.nextMeetingSubject == Self.sample.nextMeetingSubject)
        #expect(decoded.nextMeetingStart == Self.sample.nextMeetingStart)
        #expect(decoded.nextMeetingEnd == Self.sample.nextMeetingEnd)
        #expect(decoded.nextMeetingOrganizer == Self.sample.nextMeetingOrganizer)
        #expect(decoded.nextMeetingJoinUrl == Self.sample.nextMeetingJoinUrl)
        #expect(decoded.unreadEmailCount == Self.sample.unreadEmailCount)
        #expect(decoded.chatCount == Self.sample.chatCount)
        #expect(decoded.presence == Self.sample.presence)
        #expect(decoded.isOutOfOffice == Self.sample.isOutOfOffice)
    }

    /// `settingStatus` patches only presence + OOO, leaving the rest of the
    /// snapshot intact. This is the path the intent-driven mutation takes
    /// when the caller has no fresh summary to rebuild the snapshot from.
    @Test func settingStatusPatchesOnlyPresenceAndOOO() {
        let patched = Self.sample.settingStatus(
            presence: .doNotDisturb,
            isOutOfOffice: false
        )

        #expect(patched.presence == .doNotDisturb)
        #expect(patched.isOutOfOffice == false)
        #expect(patched.updatedAt == Self.sample.updatedAt)
        #expect(patched.nextMeetingSubject == Self.sample.nextMeetingSubject)
        #expect(patched.nextMeetingStart == Self.sample.nextMeetingStart)
        #expect(patched.nextMeetingOrganizer == Self.sample.nextMeetingOrganizer)
        #expect(patched.nextMeetingJoinUrl == Self.sample.nextMeetingJoinUrl)
        #expect(patched.unreadEmailCount == Self.sample.unreadEmailCount)
        #expect(patched.chatCount == Self.sample.chatCount)
    }
}
