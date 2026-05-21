// IntentExecutorTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
import Foundation
@testable import CheckIn

/// Pins the per-intent side effects extracted from SessionCoordinator.
/// Tests inject a recording URL opener so the deep-link route can be
/// verified without going through UIApplication.
@MainActor
struct IntentExecutorTests {

    // MARK: - Fixtures

    private final class OpenerRecorder {
        var openedURLs: [URL] = []
        var ok: Bool = true

        func opener(_ url: URL) async -> Bool {
            openedURLs.append(url)
            return ok
        }
    }

    private static func makeExecutor(matcher: ScriptedEntityMatcher = .init(),
                                     opener: OpenerRecorder = OpenerRecorder())
        -> (IntentExecutor, OpenerRecorder) {
        let executor = IntentExecutor(
            entityMatcher: matcher,
            urlOpener: { url in await opener.opener(url) }
        )
        return (executor, opener)
    }

    private static func meeting(joinUrl: String?) -> Meeting {
        Meeting(subject: "Standup", organizer: "Tony",
                location: "", start: Date(), end: Date(),
                isOnline: true, attendees: [], joinUrl: joinUrl)
    }

    private static func email(from: String, subject: String = "Hi",
                              fromAddress: String = "tony@example.com",
                              received: Date = Date()) -> Email {
        Email(id: UUID().uuidString, subject: subject, from: from,
              fromAddress: fromAddress, preview: "", received: received)
    }

    private static func chat(from: String, webUrl: String?) -> ChatMessage {
        ChatMessage(chatID: "c", topic: "t", from: from,
                    preview: "", sent: Date(), webUrl: webUrl)
    }

    private static func summary(meeting: Meeting? = nil,
                                emails: [Email] = [],
                                chats: [ChatMessage] = []) -> CheckInSummary {
        CheckInSummary(meeting: meeting, emails: emails, chats: chats,
                       emailError: nil, chatError: nil, teamsEnabled: true)
    }

    private static func context(with summary: CheckInSummary?) -> DialogContext {
        var ctx = DialogContext()
        ctx.summary = summary
        return ctx
    }

    private static func baseResponse() -> SpokenResponse {
        SpokenResponse(text: "", category: .answer)
    }

    private static func classified(_ intent: Intent) -> ClassifiedIntent {
        ClassifiedIntent(intent: intent, confidence: 1.0)
    }

    // MARK: - .exit forces idle

    @Test func exitForcesIdleEvenInConversationMode() async {
        let (executor, _) = Self.makeExecutor()
        let (_, rest) = await executor.resolveSideEffects(
            classified: Self.classified(.exit),
            utterance: "done",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: nil),
            defaultRest: .listening
        )
        #expect(rest == .idle)
    }

    // MARK: - non-executor intents pass baseResponse through

    @Test func nonHandledIntentReturnsBaseResponseAndDefaultRest() async {
        let (executor, opener) = Self.makeExecutor()
        let base = SpokenResponse(text: "Three unread.", category: .summary)
        let (response, rest) = await executor.resolveSideEffects(
            classified: Self.classified(.summary),
            utterance: "anything new",
            baseResponse: base,
            context: Self.context(with: Self.summary()),
            defaultRest: .listening
        )
        #expect(response.text == "Three unread.")
        #expect(rest == .listening)
        #expect(opener.openedURLs.isEmpty)
    }

    // MARK: - .open meeting

    @Test func openMeetingFiresCalendarDeepLinkWhenMeetingPresent() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(meeting: Self.meeting(joinUrl: nil))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my next meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
        // Silent success — base (empty) response passes through.
        #expect(response.text.isEmpty)
    }

    @Test func openMeetingSpeaksNoMeetingWhenAbsent() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my next meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary(meeting: nil)),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.openMeetingNone)
    }

    // MARK: - .open calendar

    @Test func openCalendarFiresCalendarDeepLink() async {
        let (executor, opener) = Self.makeExecutor()
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my calendar",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
    }

    // MARK: - .open email

    @Test func openInboxFiresInboxDeepLinkWhenNoSenderNamed() async {
        let (executor, opener) = Self.makeExecutor()
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my inbox",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookInbox)
    }

    @Test func openEmailFromKnownSenderFiresInbox() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open email from tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [Self.email(from: "Tony Smith")])
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open email from tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookInbox)
    }

    @Test func openEmailFromUnknownSenderSpeaksNotFound() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open email from tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        // Summary contains a different sender; tony has no email.
        let summary = Self.summary(emails: [Self.email(from: "Alice Smith")])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open email from tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.openNotFound("tony"))
    }

    // MARK: - .reply

    @Test func replyWithoutSenderSpeaksReplyNoSender() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.replyNoSender)
    }

    @Test func replyToKnownSenderFiresReplyDeepLinkAndSpeaksOpening() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["reply to tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [
            Self.email(from: "Tony Smith",
                       subject: "Lunch?",
                       fromAddress: "tony@example.com")
        ])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply to tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        let expectedURL = DeepLinkService.outlookReply(to: "tony@example.com",
                                                       subject: "Lunch?")
        #expect(opener.openedURLs.first == expectedURL)
        #expect(response.text == ResponseTemplateRegistry.replyOpening(to: "tony"))
    }

    @Test func replyToSenderWithNoEmailSpeaksUnknownSender() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["reply to tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [Self.email(from: "Alice Smith")])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply to tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.replyUnknownSender("tony"))
    }

    // MARK: - .join

    @Test func joinWithNoMeetingSpeaksNoneToJoin() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary(meeting: nil)),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.meetingNoneToJoin)
    }

    @Test func joinWithJoinUrlFiresPassthroughDeepLink() async {
        let (executor, opener) = Self.makeExecutor()
        let joinUrl = "https://teams.microsoft.com/l/meetup-join/abc"
        let summary = Self.summary(meeting: Self.meeting(joinUrl: joinUrl))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join the meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.passthrough(joinUrl))
        #expect(response.text.isEmpty)
    }

    @Test func joinWithoutJoinUrlFallsBackToCalendar() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(meeting: Self.meeting(joinUrl: nil))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
        #expect(response.text == ResponseTemplateRegistry.meetingNoJoinLink)
    }

    @Test func joinFailureSpeaksJoinFailed() async {
        let opener = OpenerRecorder()
        opener.ok = false
        let (executor, _) = Self.makeExecutor(opener: opener)
        let joinUrl = "https://teams.microsoft.com/l/meetup-join/abc"
        let summary = Self.summary(meeting: Self.meeting(joinUrl: joinUrl))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(response.text == ResponseTemplateRegistry.meetingJoinFailed)
    }

    // MARK: - .open chat

    @Test func openChatWithMatchingTeamsUrlFiresPassthrough() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open chat with tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let webUrl = "https://teams.microsoft.com/l/chat/abc"
        let summary = Self.summary(chats: [Self.chat(from: "Tony Smith", webUrl: webUrl)])
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open chat with tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.passthrough(webUrl))
    }
}
