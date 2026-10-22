// WatchPresencePinWireTests.swift
// BlickKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import BlickKit

struct WatchPresencePinWireTests {
    private let suite = "com.excelano.blick.tests.pinwire.\(UUID().uuidString)"
    private var store: PreferredPresenceStore { PreferredPresenceStore(suite: suite) }

    private func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @Test func offlineReportPinsTheStore() {
        defer { tearDown() }
        store.record(watchReport: WatchPresencePinWire.report(for: .offline))
        #expect(store.current()?.presence == .offline)
    }

    @Test func autoReportClearsThePin() {
        defer { tearDown() }
        store.pin(.offline)
        store.record(watchReport: WatchPresencePinWire.report(for: .unknown))
        #expect(store.current() == nil)
    }

    @Test func unrecognisedReportChangesNothing() {
        defer { tearDown() }
        store.pin(.busy)
        store.record(watchReport: "gibberish")
        #expect(store.current()?.presence == .busy)
    }
}
