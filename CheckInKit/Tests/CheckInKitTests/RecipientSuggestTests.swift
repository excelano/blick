// RecipientSuggestTests.swift
// CheckInKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import CheckInKit

struct RecipientSuggestTests {

    private let book = [
        AddressBookEntry(name: "Alice Adams", address: "alice@excelano.com"),
        AddressBookEntry(name: "Bob Baker", address: "bob@excelano.com"),
        AddressBookEntry(name: "Carol Chen", address: "carol@outside.com"),
    ]

    // MARK: activeToken

    @Test func activeTokenIsFragmentAfterLastSeparator() {
        #expect(RecipientSuggest.activeToken(in: "alice@x.com, bo") == "bo")
        #expect(RecipientSuggest.activeToken(in: "bob") == "bob")
        #expect(RecipientSuggest.activeToken(in: "alice@x.com; carol") == "carol")
    }

    @Test func activeTokenEmptyAfterSeparator() {
        #expect(RecipientSuggest.activeToken(in: "alice@x.com, ").isEmpty)
        #expect(RecipientSuggest.activeToken(in: "").isEmpty)
    }

    // MARK: completing

    @Test func completingReplacesTokenKeepingPriorRecipients() {
        #expect(RecipientSuggest.completing("alice@x.com, bo", with: "bob@excelano.com")
                == "alice@x.com, bob@excelano.com, ")
    }

    @Test func completingFromBareTokenReplacesWhole() {
        #expect(RecipientSuggest.completing("bo", with: "bob@excelano.com") == "bob@excelano.com, ")
    }

    // MARK: matches

    @Test func matchesByNameAndAddress() {
        #expect(RecipientSuggest.matches(for: "ali", in: book) == [book[0]])
        #expect(RecipientSuggest.matches(for: "bob@", in: book) == [book[1]])
    }

    @Test func matchesRankPrefixAboveContains() {
        let entries = [
            AddressBookEntry(name: "Manager Bob", address: "mbob@x.com"),   // contains "bob"
            AddressBookEntry(name: "Bob Baker", address: "bob@x.com"),      // prefix "bob"
        ]
        #expect(RecipientSuggest.matches(for: "bob", in: entries).first == entries[1])
    }

    @Test func matchesDedupeByAddressAndCapAtLimit() {
        let dupes = [
            AddressBookEntry(name: "Bob", address: "bob@x.com"),
            AddressBookEntry(name: "Bob B", address: "BOB@X.COM"),
        ]
        #expect(RecipientSuggest.matches(for: "bob", in: dupes).count == 1)
        #expect(RecipientSuggest.matches(for: "a", in: book, limit: 1).count == 1)
    }

    @Test func matchesEmptyForBlankQuery() {
        #expect(RecipientSuggest.matches(for: "  ", in: book).isEmpty)
    }
}
