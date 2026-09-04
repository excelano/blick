// StarredSenderStoreTests.swift
// BlickKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import BlickKit

/// Each test gets its own defaults suite and wipes it afterwards, so tests
/// neither see each other's stars nor leave any behind on the machine.
struct StarredSenderStoreTests {
    private let suite = "com.excelano.blick.tests.starred.\(UUID().uuidString)"
    private var store: StarredSenderStore { StarredSenderStore(suite: suite) }

    private func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    // MARK: StarredSender

    @Test func normalisesAddressAndTrimsName() {
        let sender = StarredSender(displayName: "  Ada Lovelace ", address: " Ada@Example.COM ")
        #expect(sender.address == "ada@example.com")
        #expect(sender.displayName == "Ada Lovelace")
        #expect(sender.id == "ada@example.com")
    }

    @Test func blankNameFallsBackToAddress() {
        let sender = StarredSender(displayName: "   ", address: "ada@example.com")
        #expect(sender.displayName == "ada@example.com")
    }

    // MARK: Store

    @Test func startsEmpty() {
        defer { tearDown() }
        #expect(store.all().isEmpty)
        #expect(!store.isStarred(address: "ada@example.com"))
    }

    @Test func starThenUnstar() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "Ada Lovelace", address: "ada@example.com"))
        #expect(store.isStarred(address: "ada@example.com"))
        #expect(store.all().count == 1)

        store.unstar(address: "ada@example.com")
        #expect(!store.isStarred(address: "ada@example.com"))
        #expect(store.all().isEmpty)
    }

    @Test func matchesAddressRegardlessOfCaseAndWhitespace() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "Ada", address: "ada@example.com"))
        #expect(store.isStarred(address: "ADA@Example.com"))
        #expect(store.isStarred(address: "  ada@example.com\n"))
        store.unstar(address: "ADA@EXAMPLE.COM")
        #expect(store.all().isEmpty)
    }

    @Test func matchesDisplayNameCaseInsensitively() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "Ada Lovelace", address: "ada@example.com"))
        #expect(store.isStarred(displayName: "ada lovelace"))
        #expect(store.isStarred(displayName: " Ada Lovelace "))
        #expect(!store.isStarred(displayName: "Ada"))
        #expect(!store.isStarred(displayName: ""))
    }

    @Test func restarringReplacesDisplayNameWithoutDuplicating() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "A. Lovelace", address: "ada@example.com"))
        store.star(StarredSender(displayName: "Ada Lovelace", address: "Ada@Example.com"))
        let all = store.all()
        #expect(all.count == 1)
        #expect(all.first?.displayName == "Ada Lovelace")
    }

    @Test func ignoresEmptyAddress() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "Nobody", address: "  "))
        #expect(store.all().isEmpty)
        #expect(!store.isStarred(address: ""))
    }

    @Test func ordersByNameThenAddress() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "grace", address: "grace@example.com"))
        store.star(StarredSender(displayName: "Ada", address: "ada@example.com"))
        store.star(StarredSender(displayName: "Ada", address: "ada@another.example"))
        #expect(store.all().map(\.address) == ["ada@another.example", "ada@example.com", "grace@example.com"])
    }

    @Test func unstarringUnknownAddressIsHarmless() {
        defer { tearDown() }
        store.star(StarredSender(displayName: "Ada", address: "ada@example.com"))
        store.unstar(address: "nobody@example.com")
        #expect(store.all().count == 1)
    }
}
