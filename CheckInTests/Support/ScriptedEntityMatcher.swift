// ScriptedEntityMatcher.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
@testable import CheckIn

/// EntityMatcher stub for tests that need fine-grained control of returns.
/// Maps a `(text, domain)` request to canned matches. Tests that don't need
/// matching at all can keep using `StubEntityMatcher` from the main target.
struct ScriptedEntityMatcher: EntityMatcher {
    var ordinalForText: [String: EntityMatch] = [:]
    var personForText: [String: [EntityMatch]] = [:]

    func match(text: String, domain: EntityDomain, context: DialogContext) -> [EntityMatch] {
        switch domain {
        case .ordinal:
            if let single = ordinalForText[text] { return [single] }
            return []
        case .person:
            return personForText[text] ?? []
        default:
            return []
        }
    }
}
