// InboxActions.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Touch-driven operations on the inbox: mark read, flag, refresh. Calls
/// Graph directly and publishes results into the state machine's context
/// so the view re-renders. No voice involvement — taps and swipes route
/// here without going through the speech / intent classification / state
/// machine substates that the voice path uses today. The voice path will
/// be re-pointed at the same methods in a subsequent step so both inputs
/// share one execution path.
///
/// Mutations are optimistic: the displayed unread set updates immediately,
/// the Graph call runs in the background, and a failure restores the row.
@MainActor
final class InboxActions {
    private let graphClient: GraphClient
    private let summaryService: any SummaryService
    private let stateMachine: StateMachine

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "actions")

    init(graphClient: GraphClient,
         summaryService: any SummaryService,
         stateMachine: StateMachine) {
        self.graphClient = graphClient
        self.summaryService = summaryService
        self.stateMachine = stateMachine
    }

    /// Mark an email read. Optimistic — removes the email from the
    /// displayed unread set immediately, then writes to Graph. A failure
    /// reinserts the row in received-time order and logs the error.
    func markRead(emailId: String) async {
        guard let removed = removeEmail(emailId: emailId) else { return }
        do {
            try await graphClient.markEmailRead(id: emailId)
            #if DEBUG
            print("[actions] markRead ok id=\(emailId)")
            #endif
        } catch {
            logger.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[actions] markRead failed: \(error.localizedDescription)")
            #endif
            restoreEmail(removed)
        }
    }

    /// Add a follow-up flag. Doesn't change the unread set, so there's no
    /// row to remove or restore — the operation succeeds or fails silently
    /// into the log.
    func flag(emailId: String) async {
        do {
            try await graphClient.flagEmail(id: emailId)
            #if DEBUG
            print("[actions] flag ok id=\(emailId)")
            #endif
        } catch {
            logger.error("flag failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[actions] flag failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Re-fetch the summary and publish it. The pull-to-refresh entry
    /// point. Errors inside `fetchSummary` collapse into the summary's
    /// per-stream error slots; the call itself never throws.
    func refresh() async {
        let summary = await summaryService.fetchSummary()
        stateMachine.updateContext { context in
            context.summary = summary
            context.summaryFetchedAt = Date()
        }
        #if DEBUG
        print("[actions] refresh ok emails=\(summary.emails.count) chats=\(summary.chats.count)")
        #endif
    }

    // MARK: - Optimistic helpers

    private func removeEmail(emailId: String) -> Email? {
        guard let summary = stateMachine.context.summary,
              let index = summary.emails.firstIndex(where: { $0.id == emailId }) else {
            return nil
        }
        let removed = summary.emails[index]
        var emails = summary.emails
        emails.remove(at: index)
        stateMachine.updateContext {
            $0.summary = rebuilt(summary, withEmails: emails)
        }
        return removed
    }

    private func restoreEmail(_ email: Email) {
        guard let summary = stateMachine.context.summary else { return }
        var emails = summary.emails
        // Insert in received-time desc position to preserve ordering —
        // Graph returns desc and ordinals downstream assume it.
        let index = emails.firstIndex(where: { $0.received < email.received }) ?? emails.count
        emails.insert(email, at: index)
        stateMachine.updateContext {
            $0.summary = rebuilt(summary, withEmails: emails)
        }
    }

    /// `CheckInSummary` is immutable; rebuilding with a new emails array
    /// is the only way to publish a change. The non-email fields ride
    /// through unchanged.
    private func rebuilt(_ summary: CheckInSummary, withEmails emails: [Email]) -> CheckInSummary {
        CheckInSummary(
            meeting: summary.meeting,
            emails: emails,
            chats: summary.chats,
            emailError: summary.emailError,
            chatError: summary.chatError,
            teamsEnabled: summary.teamsEnabled
        )
    }
}
