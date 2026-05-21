// ResponseTemplateRegistryTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
import Foundation
@testable import CheckIn

/// Pins the registry's pure-function surface. The pools themselves are
/// just static arrays of strings — the value-add tests are the
/// per-domain template builders and the anti-repeat picker behavior in
/// `PersonaResponseGenerator`, which is what callers actually see.
struct ResponseTemplateRegistryTests {

    // MARK: - Pool sanity

    @Test func refusalPoolNonEmpty() {
        #expect(!ResponseTemplateRegistry.refusals.isEmpty)
    }

    @Test func everyRedirectPoolIsPopulated() {
        #expect(!ResponseTemplateRegistry.readContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.summarizeContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.analyzeContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.voiceReplyRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.listBrowseRedirects.isEmpty)
    }

    // MARK: - Disambiguation prompts

    @Test func disambiguationPromptListsAllCandidates() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "tony.smith"),
            Candidate(label: "Tony Jones", entityRef: "tony.jones")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony"))
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Tony Jones"))
    }

    @Test func disambiguationPromptUsesOrSeparatorForTwo() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony Smith or Tony Jones"))
    }

    @Test func disambiguationPromptUsesOxfordForThreePlus() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b"),
            Candidate(label: "Tony Park", entityRef: "c")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony Smith, Tony Jones, or Tony Park"))
    }

    @Test func disambiguationRetryOmitsAmbiguityPreamble() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let retry = ResponseTemplateRegistry.disambiguationRetry(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(retry.contains("I missed that"))
        #expect(retry.contains("Tony Smith"))
        #expect(retry.contains("Tony Jones"))
    }

    // MARK: - Filter / open templates

    @Test func filterUnknownSenderNamesTheTokenBack() {
        let text = ResponseTemplateRegistry.filterUnknownSender("Microsoft")
        #expect(text.contains("Microsoft"))
        #expect(text.contains("inbox"))
    }

    @Test func openNotFoundMentionsRefresh() {
        let text = ResponseTemplateRegistry.openNotFound("Tony")
        #expect(text.contains("Tony"))
        #expect(text.contains("refresh") || text.contains("Refresh"))
    }

    // MARK: - Reply templates

    @Test func replyOpeningCallsOutOutlook() {
        let text = ResponseTemplateRegistry.replyOpening(to: "Tony Smith")
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Outlook"))
    }

    @Test func replyUnknownSenderNamesTheToken() {
        let text = ResponseTemplateRegistry.replyUnknownSender("Microsoft")
        #expect(text.contains("Microsoft"))
    }

    // MARK: - Confirmation

    @Test func confirmationPromptRestatesDescription() {
        let text = ResponseTemplateRegistry.confirmationPrompt("mark Tony's email as read")
        #expect(text.contains("mark Tony's email as read"))
        // Ends with a question shape so the user knows a yes/no is expected.
        #expect(text.contains("?"))
    }

    @Test func successAnnouncementRestatesDescription() {
        let text = ResponseTemplateRegistry.successAnnouncement("flagged Tony's email")
        #expect(text.contains("flagged Tony's email"))
    }

    @Test func confirmationCancelledIsShort() {
        // Short, terminal — outcome is the answer; the speech is just ack.
        #expect(ResponseTemplateRegistry.confirmationCancelled.count < 30)
    }

    // MARK: - Domain detection

    @Test func detectDomainEmailWord() {
        #expect(ResponseTemplateRegistry.detectDomain("any new emails") == .email)
    }

    @Test func detectDomainChatWord() {
        #expect(ResponseTemplateRegistry.detectDomain("any teams chats") == .chat)
    }

    @Test func detectDomainMeetingWord() {
        #expect(ResponseTemplateRegistry.detectDomain("anything on my calendar") == .meeting)
    }

    @Test func detectDomainAmbiguousFallsToAll() {
        // 'meeting' and 'email' both hit → ambiguous → .all
        #expect(ResponseTemplateRegistry.detectDomain("emails and meetings") == .all)
    }

    @Test func detectDomainNoSignalFallsToAll() {
        #expect(ResponseTemplateRegistry.detectDomain("anything new") == .all)
    }

    // The "messages" token alone routes to Outlook (the dominant register
    // in M365 voice queries). Teams-flavored phrasings that contain
    // "messages" route to Teams; Outlook-flavored phrasings stay Outlook.

    @Test func detectDomainBareMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many messages do I have") == .email)
    }

    @Test func detectDomainEmailMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many email messages") == .email)
    }

    @Test func detectDomainUnreadMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many unread messages") == .email)
    }

    @Test func detectDomainNewMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("any new messages") == .email)
    }

    @Test func detectDomainChatMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many chat messages") == .chat)
    }

    @Test func detectDomainTeamsMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many teams messages") == .chat)
    }

    @Test func detectDomainPendingMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many pending messages") == .chat)
    }

    // MARK: - Summary phrasing

    @Test func summarySentenceHandlesZeroUnread() {
        let summary = Fixtures.summary()
        let text = ResponseTemplateRegistry.summarySentence(from: summary)
        #expect(text.contains("No unread"))
    }

    @Test func summarySentenceSpellsTwoUnread() {
        let summary = Fixtures.summary(emails: [
            ("Tony Smith", "A"),
            ("Sarah Park", "B")
        ])
        let text = ResponseTemplateRegistry.summarySentence(from: summary)
        #expect(text.contains("Two unread"))
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Sarah Park"))
    }

    @Test func summaryFilteredBySenderEmptyMatch() {
        let summary = Fixtures.summary(emails: [("Tony Smith", "A")])
        let text = ResponseTemplateRegistry.summaryFilteredBySender(
            from: summary, matching: "Bob", utterance: "anything from bob"
        )
        #expect(text.contains("Bob"))
        #expect(text.lowercased().contains("nothing"))
    }

    @Test func summaryFilteredBySenderSingleMatch() {
        let summary = Fixtures.summary(emails: [
            ("Tony Smith", "Project update")
        ])
        let text = ResponseTemplateRegistry.summaryFilteredBySender(
            from: summary, matching: "Tony Smith", utterance: "any from tony"
        )
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Project update"))
    }

    // MARK: - Bulk mutation phrasing

    @Test func bulkMutationDescriptionNoSenderUsesAll() {
        let text = ResponseTemplateRegistry.bulkMutationDescription(
            kind: .bulkMarkRead, count: 12, sender: nil, exceptLatest: false)
        #expect(text.contains("12"))
        #expect(text.lowercased().contains("all"))
        #expect(text.contains("emails"))
        #expect(text.contains("as read"))
    }

    @Test func bulkMutationDescriptionWithSenderNamesSender() {
        let text = ResponseTemplateRegistry.bulkMutationDescription(
            kind: .bulkDelete, count: 8, sender: "Microsoft", exceptLatest: false)
        #expect(text.contains("Microsoft"))
        #expect(text.lowercased().contains("eight"))
        #expect(text.lowercased().contains("delete"))
    }

    @Test func bulkMutationDescriptionExceptLatestAppendsCarveOut() {
        let text = ResponseTemplateRegistry.bulkMutationDescription(
            kind: .bulkDelete, count: 7, sender: "Microsoft", exceptLatest: true)
        #expect(text.contains("Microsoft"))
        #expect(text.lowercased().contains("seven"))
        #expect(text.contains("keep the latest one"))
    }

    @Test func bulkMutationDescriptionSingularNoun() {
        // One target reads "one email" not "one emails". Hits the count==1
        // singular branch.
        let text = ResponseTemplateRegistry.bulkMutationDescription(
            kind: .bulkFlag, count: 1, sender: "Microsoft", exceptLatest: false)
        #expect(text.contains("email"))
        #expect(!text.contains("emails"))
    }

    // MARK: - Advanced count predicates

    @Test func detectAdvancedCountRecognizesToday() {
        #expect(ResponseTemplateRegistry.detectAdvancedCount("how many today") == .today)
        #expect(ResponseTemplateRegistry.detectAdvancedCount("any from today") == .today)
    }

    @Test func detectAdvancedCountRecognizesThisMorning() {
        // "this morning" is a sub-window of "today" — verify it wins.
        #expect(ResponseTemplateRegistry.detectAdvancedCount("how many this morning") == .thisMorning)
    }

    @Test func detectAdvancedCountRecognizesLastHour() {
        #expect(ResponseTemplateRegistry.detectAdvancedCount("how many in the last hour") == .lastHour)
        #expect(ResponseTemplateRegistry.detectAdvancedCount("anything in the past hour") == .lastHour)
    }

    @Test func detectAdvancedCountReturnsNilForUnrelated() {
        #expect(ResponseTemplateRegistry.detectAdvancedCount("how many emails") == nil)
        #expect(ResponseTemplateRegistry.detectAdvancedCount("anything from tony") == nil)
    }

    @Test func countEmailsTodayFiltersByDay() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now).addingTimeInterval(8 * 3600)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let emails: [Email] = [
            Email(id: "1", subject: "", from: "A", fromAddress: "a@x",
                  preview: "", received: today),
            Email(id: "2", subject: "", from: "B", fromAddress: "b@x",
                  preview: "", received: yesterday)
        ]
        let count = ResponseTemplateRegistry.countEmails(emails, matching: .today)
        #expect(count == 1)
    }

    @Test func countEmailsLastHourFiltersByCutoff() {
        let now = Date()
        let recent = now.addingTimeInterval(-10 * 60)        // 10 min ago
        let stale = now.addingTimeInterval(-2 * 3600)        // 2 hr ago
        let emails: [Email] = [
            Email(id: "1", subject: "", from: "A", fromAddress: "a@x",
                  preview: "", received: recent),
            Email(id: "2", subject: "", from: "B", fromAddress: "b@x",
                  preview: "", received: stale)
        ]
        let count = ResponseTemplateRegistry.countEmails(emails, matching: .lastHour)
        #expect(count == 1)
    }

    @Test func advancedCountResponseZeroToday() {
        let text = ResponseTemplateRegistry.advancedCountResponse(
            count: 0, predicate: .today)
        #expect(text.lowercased().contains("nothing"))
        #expect(text.lowercased().contains("today"))
    }

    @Test func advancedCountResponseOneLastHour() {
        let text = ResponseTemplateRegistry.advancedCountResponse(
            count: 1, predicate: .lastHour)
        #expect(text.contains("One"))
        #expect(text.contains("last hour"))
    }

    @Test func advancedCountResponseManyThisMorning() {
        let text = ResponseTemplateRegistry.advancedCountResponse(
            count: 4, predicate: .thisMorning)
        #expect(text.contains("Four"))
        #expect(text.contains("this morning"))
    }
}
