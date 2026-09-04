// StarredSenderStore.swift
// BlickKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// A sender the user has singled out. Display name plus address, nothing
/// more: this exists only as far as the new-message nudge's "starred senders
/// only" filter needs, and is deliberately not a contacts list.
///
/// The address is the identity. It is stored lowercased and trimmed so that
/// the same mailbox written two ways by two mail clients still matches, and
/// starring an address a second time replaces the display name rather than
/// adding a duplicate.
public struct StarredSender: Codable, Hashable, Identifiable, Sendable {
    public let address: String
    public let displayName: String

    public var id: String { address }

    /// Builds a normalised entry. A blank display name falls back to the
    /// address so every row has something to show.
    public init(displayName: String, address: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = Self.normalize(address)
        self.displayName = name.isEmpty ? self.address : name
    }

    /// The comparison form of an address: trimmed and lowercased.
    public static func normalize(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// The starred set, persisted in the shared App Group as one JSON array.
///
/// Lives in the App Group rather than standard defaults for the same reason
/// `PreferredPresenceStore` does: the background-refresh task and the app
/// process must read the same set, and any extension that later wants it
/// can. It carries no dependency and makes no Graph call, which is what
/// makes it the one piece of this release with plain unit tests.
///
/// Matching offers two shapes because the two channels expose different
/// things. Mail carries an SMTP address, so mail matches on `address`. Teams
/// chat messages carry only the sender's display name, so chat matches on
/// `displayName`; that is looser, but it is what Graph gives us there.
public struct StarredSenderStore: Sendable {
    private let suite: String

    public init(suite: String = BlickSnapshot.appGroupIdentifier) {
        self.suite = suite
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    private static let key = "starredSenders"

    /// Every starred sender, ordered for display: by name, case-insensitively,
    /// then by address so ties are stable.
    public func all() -> [StarredSender] {
        load().sorted {
            let byName = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return byName == .orderedSame ? $0.address < $1.address : byName == .orderedAscending
        }
    }

    public func isStarred(address: String) -> Bool {
        let wanted = StarredSender.normalize(address)
        guard !wanted.isEmpty else { return false }
        return load().contains { $0.address == wanted }
    }

    public func isStarred(displayName: String) -> Bool {
        let wanted = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return false }
        return load().contains { $0.displayName.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// Add a sender, or refresh the display name of one already starred.
    /// A sender with an empty address is ignored: there would be nothing
    /// for mail to match on, and the row could never be unstarred by address.
    public func star(_ sender: StarredSender) {
        guard !sender.address.isEmpty else { return }
        var senders = load()
        senders.removeAll { $0.address == sender.address }
        senders.append(sender)
        save(senders)
    }

    public func unstar(address: String) {
        let wanted = StarredSender.normalize(address)
        var senders = load()
        senders.removeAll { $0.address == wanted }
        save(senders)
    }

    private func load() -> [StarredSender] {
        guard let defaults, let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([StarredSender].self, from: data)) ?? []
    }

    private func save(_ senders: [StarredSender]) {
        guard let defaults else { return }
        if senders.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(senders) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
