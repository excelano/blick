// Inbox.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

@MainActor @Observable
final class Inbox {
    private(set) var summary: CheckInSummary?

    private let graphClient: GraphClient
    private let teamsEnabled: Bool
    private var didFetchUserID = false

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin", category: "inbox")

    init(graphClient: GraphClient, teamsEnabled: Bool) {
        self.graphClient = graphClient
        self.teamsEnabled = teamsEnabled
    }

    func refresh() async {
        var userIDReady = !teamsEnabled || didFetchUserID
        if teamsEnabled && !didFetchUserID {
            do {
                try await graphClient.fetchUserID()
                didFetchUserID = true
                userIDReady = true
            } catch {
                logger.error("fetchUserID failed: \(error.localizedDescription, privacy: .public)")
                userIDReady = false
            }
        }

        async let meeting = fetchMeeting()
        async let emails = fetchEmails()
        async let chats = fetchChats(userIDReady: userIDReady)
        let emailsResult = await emails
        summary = CheckInSummary(meeting: await meeting,
                                 emails: emailsResult.emails,
                                 chats: await chats,
                                 totalUnreadEmails: emailsResult.totalCount)
    }

    /// Optimistic: drops the row immediately, restores it (in received-time
    /// order) if the Graph PATCH fails.
    func markRead(emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let removed = summary?.emails.remove(at: idx) else { return }
        summary?.totalUnreadEmails -= 1
        do {
            try await graphClient.markEmailRead(id: emailId)
        } catch {
            logger.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            let insertAt = summary?.emails.firstIndex(where: { $0.received < removed.received })
                ?? summary?.emails.count ?? 0
            summary?.emails.insert(removed, at: insertAt)
            summary?.totalUnreadEmails += 1
        }
    }

    /// Optimistic. Caller passes the desired state rather than asking us to
    /// flip what we read, so rapid double-swipes can't oscillate against
    /// stale state.
    func setFlagged(_ flagged: Bool, emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let original = summary?.emails[idx] else { return }
        summary?.emails[idx] = original.with(isFlagged: flagged)
        do {
            if flagged {
                try await graphClient.flagEmail(id: emailId)
            } else {
                try await graphClient.unflagEmail(id: emailId)
            }
        } catch {
            logger.error("setFlagged(\(flagged)) failed: \(error.localizedDescription, privacy: .public)")
            summary?.emails[idx] = original
        }
    }

    private func fetchMeeting() async -> Meeting? {
        do {
            return try await graphClient.nextMeeting()
        } catch {
            logger.error("nextMeeting failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchEmails() async -> (emails: [Email], totalCount: Int) {
        do {
            return try await graphClient.unreadEmails()
        } catch {
            logger.error("unreadEmails failed: \(error.localizedDescription, privacy: .public)")
            return ([], 0)
        }
    }

    /// Returns an empty array when Teams is disabled or `fetchUserID` failed
    /// — the pending-chat heuristic compares against the signed-in user's
    /// ID, so without that the call can't be made meaningfully.
    private func fetchChats(userIDReady: Bool) async -> [ChatMessage] {
        guard teamsEnabled, userIDReady else { return [] }
        do {
            return try await graphClient.pendingChats()
        } catch {
            logger.error("pendingChats failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
