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
    private var lastRefreshedAt: Date?

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
        lastRefreshedAt = Date()
    }

    /// Skip the refresh if the last one finished within `threshold` seconds.
    /// Used by the scene-foreground hook so quick app-switches don't trigger
    /// back-to-back Graph fetches.
    func refreshIfStale(threshold: TimeInterval = 30) async {
        if let last = lastRefreshedAt, Date().timeIntervalSince(last) < threshold {
            return
        }
        await refresh()
    }

    /// Optimistically clears the visible email list, sends a single Graph
    /// `$batch` PATCH, and re-inserts only the emails that came back
    /// non-2xx. Uses `$batch` rather than fanning 20 concurrent PATCHes
    /// because Graph rate-limits bursts and silently drops some.
    func markAllVisibleRead() async {
        let preserved = summary?.emails ?? []
        let ids = preserved.map(\.id)
        guard !ids.isEmpty else { return }

        summary?.emails = []
        summary?.totalUnreadEmails -= ids.count

        do {
            let failed = try await graphClient.batchMarkRead(ids: ids)
            let toRestore = preserved.filter { failed.contains($0.id) }
            if !toRestore.isEmpty {
                summary?.emails = toRestore
                summary?.totalUnreadEmails += toRestore.count
                logger.error("markAllVisibleRead: \(toRestore.count) of \(ids.count) failed")
            }
            // Top up from the server when there are still-unread emails
            // beyond what we had cached (the "N more unread" footer's set).
            // Otherwise the user is left looking at an empty email section
            // that pull-to-refresh would fix.
            if let s = summary, s.totalUnreadEmails > s.emails.count {
                let result = await fetchEmails()
                summary?.emails = result.emails
                summary?.totalUnreadEmails = result.totalCount
            }
        } catch {
            logger.error("markAllVisibleRead failed: \(error.localizedDescription, privacy: .public)")
            summary?.emails = preserved
            summary?.totalUnreadEmails += ids.count
        }
    }

    /// Optimistically flips the flag on every visible email not already in
    /// the target state, sends a single Graph `$batch` PATCH, and reverts
    /// only the emails that came back non-2xx.
    func setFlaggedAllVisible(_ flagged: Bool) async {
        let targets = (summary?.emails ?? []).filter { $0.isFlagged != flagged }
        let ids = Set(targets.map(\.id))
        guard !ids.isEmpty else { return }

        flipFlagged(matching: ids, to: flagged)

        do {
            let failed = try await graphClient.batchSetFlagged(ids: Array(ids), flagged: flagged)
            if !failed.isEmpty {
                flipFlagged(matching: failed, to: !flagged)
                logger.error("setFlaggedAllVisible(\(flagged)): \(failed.count) of \(ids.count) failed")
            }
        } catch {
            logger.error("setFlaggedAllVisible(\(flagged)) failed: \(error.localizedDescription, privacy: .public)")
            flipFlagged(matching: ids, to: !flagged)
        }
    }

    private func flipFlagged(matching ids: Set<String>, to flagged: Bool) {
        guard var current = summary?.emails else { return }
        for i in current.indices where ids.contains(current[i].id) {
            current[i] = current[i].with(isFlagged: flagged)
        }
        summary?.emails = current
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

    /// Optimistic. Mutates `summary.meeting.responseStatus` immediately so
    /// the UI swaps to the responded pill, and reverts on failure. After a
    /// successful RSVP, also marks any invite emails still sitting unread
    /// in the inbox as read.
    func respondToMeeting(_ response: MeetingResponse) async {
        guard let meeting = summary?.meeting else { return }
        let previous = meeting.responseStatus
        summary?.meeting = meeting.with(responseStatus: response)
        do {
            try await graphClient.respondToMeeting(id: meeting.id, response: response)
            await markMatchingInviteEmailsRead(for: meeting)
        } catch {
            logger.error("respondToMeeting(\(response.rawValue)) failed: \(error.localizedDescription, privacy: .public)")
            summary?.meeting = meeting.with(responseStatus: previous)
        }
    }

    /// Subject-matches against the three invite-side forms Outlook uses
    /// ("Sprint Planning", "Updated: Sprint Planning", "Cancelled: Sprint
    /// Planning"). Bounded to the local unread list, so it can't reach
    /// beyond the 20 newest emails we already have.
    private func markMatchingInviteEmailsRead(for meeting: Meeting) async {
        let target = meeting.subject.lowercased()
        let acceptable: Set<String> = [target, "updated: \(target)", "cancelled: \(target)"]
        let matchIds = (summary?.emails ?? [])
            .filter { acceptable.contains($0.subject.lowercased()) }
            .map(\.id)
        for id in matchIds {
            await markRead(emailId: id)
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
