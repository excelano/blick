// EmailAddressValidationTests.swift
// CheckInKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import CheckInKit

struct EmailAddressValidationTests {

    // MARK: isValid

    @Test func acceptsOrdinaryAddress() {
        #expect(EmailAddressValidation.isValid("david@excelano.com"))
        #expect(EmailAddressValidation.isValid("first.last+tag@sub.domain.co.uk"))
    }

    @Test func rejectsMissingParts() {
        #expect(!EmailAddressValidation.isValid(""))
        #expect(!EmailAddressValidation.isValid("noatsign.com"))
        #expect(!EmailAddressValidation.isValid("@excelano.com"))
        #expect(!EmailAddressValidation.isValid("david@"))
        #expect(!EmailAddressValidation.isValid("two@@signs.com"))
    }

    @Test func rejectsDomainWithoutDot() {
        #expect(!EmailAddressValidation.isValid("david@localhost"))
    }

    @Test func rejectsLeadingOrTrailingDotDomain() {
        #expect(!EmailAddressValidation.isValid("david@.com"))
        #expect(!EmailAddressValidation.isValid("david@excelano."))
    }

    @Test func rejectsEmbeddedSpace() {
        #expect(!EmailAddressValidation.isValid("da vid@excelano.com"))
    }

    // MARK: normalized

    @Test func normalizedTrimsWhitespace() {
        #expect(EmailAddressValidation.normalized("  david@excelano.com  ") == "david@excelano.com")
    }

    @Test func normalizedUnwrapsDisplayName() {
        #expect(EmailAddressValidation.normalized("David Anderson <david@excelano.com>") == "david@excelano.com")
        #expect(EmailAddressValidation.normalized("<david@excelano.com>") == "david@excelano.com")
    }

    @Test func normalizedPreservesLocalPartCase() {
        #expect(EmailAddressValidation.normalized("David.Anderson@Excelano.com") == "David.Anderson@Excelano.com")
    }

    @Test func normalizedReturnsNilForJunk() {
        #expect(EmailAddressValidation.normalized("not an address") == nil)
        #expect(EmailAddressValidation.normalized("   ") == nil)
    }

    // MARK: parseList

    @Test func parsesCommaAndSemicolonSeparated() {
        let result = EmailAddressValidation.parseList("a@x.com, b@y.com; c@z.com")
        #expect(result.valid == ["a@x.com", "b@y.com", "c@z.com"])
        #expect(result.invalid.isEmpty)
    }

    @Test func parseListKeepsDisplayNameRecipientsIntact() {
        let result = EmailAddressValidation.parseList("David A <david@excelano.com>, Sam <sam@excelano.com>")
        #expect(result.valid == ["david@excelano.com", "sam@excelano.com"])
        #expect(result.invalid.isEmpty)
    }

    @Test func parseListSeparatesInvalidPieces() {
        let result = EmailAddressValidation.parseList("good@x.com, nope, also-bad")
        #expect(result.valid == ["good@x.com"])
        #expect(result.invalid == ["nope", "also-bad"])
    }

    @Test func parseListDeduplicatesCaseInsensitively() {
        let result = EmailAddressValidation.parseList("David@X.com, david@x.com, DAVID@X.COM")
        #expect(result.valid == ["David@X.com"])
    }

    @Test func parseListHandlesEmptyAndSeparatorOnly() {
        #expect(EmailAddressValidation.parseList("").valid.isEmpty)
        #expect(EmailAddressValidation.parseList(" , ; ").valid.isEmpty)
        #expect(EmailAddressValidation.parseList(" , ; ").invalid.isEmpty)
    }
}
