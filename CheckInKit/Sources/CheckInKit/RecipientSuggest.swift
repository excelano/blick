// RecipientSuggest.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// One name/address pair the composer can suggest. Harvested by the app from
/// the people already in the fetched mail streams — no Contacts permission,
/// nothing off-device.
public struct AddressBookEntry: Equatable, Hashable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

/// Pure logic for recipient type-ahead: extract the token being typed, rank
/// suggestions against it, and splice a chosen address back into the field.
/// The source list is local and small, so matching is synchronous — there's no
/// async race to guard against (unlike a network address-book search, which
/// would need a generation counter to keep a slow lookup from overwriting a
/// newer keystroke).
public enum RecipientSuggest {

    /// Separators between recipients in a typed field — the same set
    /// `EmailAddressValidation.parseList` splits on.
    private static let separators = CharacterSet(charactersIn: ",;\n\r")

    /// The in-progress recipient: the fragment after the last separator,
    /// trimmed. Empty when the field is empty or ends with a separator (so no
    /// suggestions show until the user starts the next name).
    public static func activeToken(in text: String) -> String {
        let tail: Substring
        if let sep = text.rangeOfCharacter(from: separators, options: .backwards) {
            tail = text[sep.upperBound...]
        } else {
            tail = text[...]
        }
        return tail.trimmingCharacters(in: .whitespaces)
    }

    /// Replace the in-progress token with `address`, leaving the already-typed
    /// recipients intact and a trailing ", " so the next name can follow.
    public static func completing(_ text: String, with address: String) -> String {
        if let sep = text.rangeOfCharacter(from: separators, options: .backwards) {
            return "\(text[...sep.lowerBound]) \(address), "
        }
        return "\(address), "
    }

    /// Entries whose name or address matches `fragment`, best first: a name or
    /// address that starts with the fragment ranks above one that merely
    /// contains it. De-duplicated by address (case-insensitive), capped at
    /// `limit`. Empty for a blank fragment.
    public static func matches(for fragment: String, in entries: [AddressBookEntry],
                               limit: Int = 5) -> [AddressBookEntry] {
        let query = fragment.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }

        var scored: [(entry: AddressBookEntry, rank: Int)] = []
        var seen = Set<String>()
        for entry in entries {
            let name = entry.name.lowercased()
            let address = entry.address.lowercased()
            let rank: Int
            if name.hasPrefix(query) || address.hasPrefix(query) {
                rank = 0
            } else if name.contains(query) || address.contains(query) {
                rank = 1
            } else {
                continue
            }
            guard seen.insert(address).inserted else { continue }
            scored.append((entry, rank))
        }
        return scored
            .enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .prefix(limit)
            .map(\.element.entry)
    }
}
