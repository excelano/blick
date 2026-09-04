// NewMessageTracker.swift
// BlickKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Which unread messages a refresh has already shown the user, so the next
/// refresh can say what is genuinely new. The nudge is built on this diff
/// rather than on "unread", because unread is a state and new is an event:
/// a message that was unread at the last refresh must not notify again.
///
/// Two rules the tests pin down. The first refresh after install or sign-in
/// seeds the set silently, so a fresh sign-in never announces the whole
/// existing inbox. And a message once seen stays seen even after it leaves
/// the unread list, so marking it unread again elsewhere does not re-notify.
/// The seen lists are capped, oldest first out, so the store cannot grow
/// without bound over months of refreshes.
///
/// Persisted in the App Group like the other stores, so the background
/// refresh task and the foreground app advance the same ledger.
public struct NewMessageTracker: Sendable {
    /// The persisted ledger. Public so the pure diff can be unit tested
    /// without defaults.
    public struct State: Codable, Equatable, Sendable {
        public var seeded: Bool
        public var emails: [String]
        public var chats: [String]

        public init(seeded: Bool = false, emails: [String] = [], chats: [String] = []) {
            self.seeded = seeded
            self.emails = emails
            self.chats = chats
        }
    }

    public struct Result: Equatable, Sendable {
        public let state: State
        public let newEmailIds: [String]
        public let newChatKeys: [String]
    }

    /// Entries kept per channel. The unread list is at most a few hundred,
    /// so this holds every id the user could still see plus a long tail.
    public static let cap = 1000

    private let suite: String

    public init(suite: String = BlickSnapshot.appGroupIdentifier) {
        self.suite = suite
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suite) }
    private static let key = "newMessageTracker"

    /// Record what this refresh saw and report what was not seen before.
    /// Pass `nil` for a channel whose fetch failed: its ledger is left as it
    /// was, since an empty list would otherwise read as "nothing unread".
    public func record(emailIds: [String]?, chatKeys: [String]?) -> Result {
        let result = Self.advance(load(), emailIds: emailIds, chatKeys: chatKeys)
        save(result.state)
        return result
    }

    /// Forget everything, so the next refresh seeds silently. Sign-out.
    public func reset() {
        defaults?.removeObject(forKey: Self.key)
    }

    /// The diff itself, free of persistence. On an unseeded ledger every id
    /// is recorded and nothing is reported new.
    public static func advance(_ state: State, emailIds: [String]?, chatKeys: [String]?) -> Result {
        var next = state
        var newEmails: [String] = []
        var newChats: [String] = []
        if let emailIds {
            (next.emails, newEmails) = merge(seen: state.emails, current: emailIds)
        }
        if let chatKeys {
            (next.chats, newChats) = merge(seen: state.chats, current: chatKeys)
        }
        if !state.seeded {
            next.seeded = true
            return Result(state: next, newEmailIds: [], newChatKeys: [])
        }
        return Result(state: next, newEmailIds: newEmails, newChatKeys: newChats)
    }

    /// Append the unseen ids in their given order, then trim from the front.
    private static func merge(seen: [String], current: [String]) -> (seen: [String], new: [String]) {
        let known = Set(seen)
        var unseen: [String] = []
        var added = Set<String>()
        for id in current where !known.contains(id) && !added.contains(id) {
            unseen.append(id)
            added.insert(id)
        }
        let merged = seen + unseen
        return (Array(merged.suffix(cap)), unseen)
    }

    private func load() -> State {
        guard let defaults, let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    private func save(_ state: State) {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
