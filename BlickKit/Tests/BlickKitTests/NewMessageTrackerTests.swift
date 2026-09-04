// NewMessageTrackerTests.swift
// BlickKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import BlickKit

struct NewMessageTrackerTests {
    private typealias State = NewMessageTracker.State

    // MARK: advance (pure)

    @Test func firstRefreshSeedsSilently() {
        let r = NewMessageTracker.advance(State(), emailIds: ["e1", "e2"], chatKeys: ["c1"])
        #expect(r.newEmailIds.isEmpty)
        #expect(r.newChatKeys.isEmpty)
        #expect(r.state.seeded)
        #expect(r.state.emails == ["e1", "e2"])
        #expect(r.state.chats == ["c1"])
    }

    @Test func reportsOnlyUnseenAfterSeeding() {
        let seeded = State(seeded: true, emails: ["e1"], chats: ["c1"])
        let r = NewMessageTracker.advance(seeded, emailIds: ["e1", "e2", "e3"], chatKeys: ["c1", "c2"])
        #expect(r.newEmailIds == ["e2", "e3"])
        #expect(r.newChatKeys == ["c2"])
        #expect(r.state.emails == ["e1", "e2", "e3"])
    }

    @Test func seenStaysSeenAfterLeavingAndReturning() {
        var state = State(seeded: true, emails: ["e1"], chats: [])
        state = NewMessageTracker.advance(state, emailIds: [], chatKeys: []).state
        let r = NewMessageTracker.advance(state, emailIds: ["e1"], chatKeys: [])
        #expect(r.newEmailIds.isEmpty)
    }

    @Test func failedChannelLeavesLedgerUntouched() {
        let seeded = State(seeded: true, emails: ["e1"], chats: ["c1"])
        let r = NewMessageTracker.advance(seeded, emailIds: nil, chatKeys: ["c1", "c2"])
        #expect(r.state.emails == ["e1"])
        #expect(r.newEmailIds.isEmpty)
        #expect(r.newChatKeys == ["c2"])
    }

    @Test func duplicateIdsInOneRefreshReportOnce() {
        let seeded = State(seeded: true)
        let r = NewMessageTracker.advance(seeded, emailIds: ["e1", "e1"], chatKeys: [])
        #expect(r.newEmailIds == ["e1"])
        #expect(r.state.emails == ["e1"])
    }

    @Test func capDropsOldestFirst() {
        let old = (0..<NewMessageTracker.cap).map { "old\($0)" }
        let seeded = State(seeded: true, emails: old)
        let r = NewMessageTracker.advance(seeded, emailIds: ["fresh"], chatKeys: [])
        #expect(r.state.emails.count == NewMessageTracker.cap)
        #expect(r.state.emails.last == "fresh")
        #expect(!r.state.emails.contains("old0"))
        #expect(r.state.emails.contains("old1"))
    }

    // MARK: persistence

    @Test func persistsAcrossInstancesAndResets() {
        let suite = "com.excelano.blick.tests.tracker.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        _ = NewMessageTracker(suite: suite).record(emailIds: ["e1"], chatKeys: [])
        let second = NewMessageTracker(suite: suite).record(emailIds: ["e1", "e2"], chatKeys: ["c1"])
        #expect(second.newEmailIds == ["e2"])
        #expect(second.newChatKeys == ["c1"])

        NewMessageTracker(suite: suite).reset()
        let afterReset = NewMessageTracker(suite: suite).record(emailIds: ["e9"], chatKeys: [])
        #expect(afterReset.newEmailIds.isEmpty)
    }
}
