// SummaryService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Pulls the three launch surfaces (next meeting, unread email, pending
/// Teams chats) into a single `CheckInSummary`. Per-stream fetch failures
/// log and collapse to an empty result for that stream — partial success
/// still produces a useful summary.
protocol SummaryService {
    func fetchSummary() async -> CheckInSummary
}

/// Microsoft Graph implementation. The three calls run in parallel via
/// `async let`; a one-shot user-ID fetch (a prerequisite for the Teams
/// pending-chat heuristic) runs serially on first use.
@MainActor
final class GraphSummaryService: SummaryService {
    private let graphClient: GraphClient
    private let teamsEnabled: Bool
    private var didFetchUserID = false

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "summary")

    init(graphClient: GraphClient, teamsEnabled: Bool) {
        self.graphClient = graphClient
        self.teamsEnabled = teamsEnabled
    }

    func fetchSummary() async -> CheckInSummary {
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

        let userIDForChats = userIDReady
        async let meetingTask: Meeting? = fetchMeetingOrNil()
        async let emailsTask: [Email] = fetchEmails()
        async let chatsTask: [ChatMessage] = fetchChats(userIDReady: userIDForChats)

        return CheckInSummary(
            meeting: await meetingTask,
            emails: await emailsTask,
            chats: await chatsTask
        )
    }

    private func fetchMeetingOrNil() async -> Meeting? {
        do {
            return try await graphClient.nextMeeting()
        } catch {
            logger.error("nextMeeting failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchEmails() async -> [Email] {
        do {
            return try await graphClient.unreadEmails()
        } catch {
            logger.error("unreadEmails failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// If `fetchUserID` failed the pending-chat heuristic can't run; the
    /// Teams scope likely isn't granted on the silent token.
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
