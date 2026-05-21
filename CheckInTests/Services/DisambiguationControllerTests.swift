// DisambiguationControllerTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the disambiguation flow at the controller level. Same scenarios
/// the side-channel-era flow used to depend on, now directed at the
/// extracted type instead of SessionCoordinator.
@MainActor
struct DisambiguationControllerTests {

    // MARK: - Fixtures

    private static let tonys: [Candidate] = [
        Candidate(label: "Tony Smith", entityRef: "Tony Smith"),
        Candidate(label: "Tony Jones", entityRef: "Tony Jones")
    ]

    private static let suspended = SuspendedIntent(utterance: "any from tony",
                                                   intent: "filter")

    private static func enterDisambiguating(_ sm: StateMachine,
                                            preferred: RestState = .idle) {
        sm.preferredRestState = preferred
        sm.transition(to: .active(.disambiguating(
            suspendedIntent: suspended,
            candidates: tonys,
            surface: "Tony")))
    }

    private static func makeController(matcher: ScriptedEntityMatcher = .init())
        -> (StateMachine, DisambiguationController) {
        let sm = StateMachine()
        let controller = DisambiguationController(
            stateMachine: sm,
            responseGenerator: StubResponseGenerator(),
            entityMatcher: matcher,
            utteranceLog: NoOpUtteranceLog()
        )
        return (sm, controller)
    }

    // MARK: - cancel

    @Test func cancelReturnsToIdleInTapToTalk() {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm, preferred: .idle)
        controller.cancel()
        #expect(sm.currentState == .active(.idle))
    }

    @Test func cancelReturnsToListeningInConversationMode() {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm, preferred: .listening)
        controller.cancel()
        #expect(sm.currentState == .active(.listening))
    }

    // MARK: - resume

    @Test func resumeRoutesThroughProcessing() async {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        controller.resume(with: Self.tonys[0])
        // Synchronous transition lands in .processing(.thinking) before the
        // Task-spawned completeFilterTurn runs.
        #expect(sm.currentState == .active(.processing(.thinking)))
    }

    @Test func resumeZerosFailedAttempts() {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        sm.updateContext { $0.disambiguationFailedAttempts = 1 }
        controller.resume(with: Self.tonys[0])
        #expect(sm.context.disambiguationFailedAttempts == 0)
    }

    @Test func resumeNoOpsWhenNotInDisambiguating() {
        let (sm, controller) = Self.makeController()
        sm.transition(to: .active(.idle))
        controller.resume(with: Self.tonys[0])
        #expect(sm.currentState == .active(.idle))
    }

    // MARK: - handleUtterance — cancel terms

    @Test func handleUtteranceCancelTermRoutesToRest() async {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("never mind",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        #expect(sm.currentState == .active(.idle))
    }

    // MARK: - handleUtterance — ordinal pick

    @Test func handleUtteranceOrdinalPicksCorrectCandidate() async {
        var matcher = ScriptedEntityMatcher()
        matcher.ordinalForText["the first one"] = EntityMatch(
            surface: "first", canonical: "1", confidence: 0.9)
        let (sm, controller) = Self.makeController(matcher: matcher)
        Self.enterDisambiguating(sm)

        await controller.handleUtterance("the first one",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // resume(with:) was invoked synchronously inside handleUtterance —
        // the state machine sits in .processing while completeFilterTurn
        // races. Either .processing or the subsequent .speaking is fine
        // proof that the resume path fired.
        switch sm.currentState {
        case .active(.processing), .active(.speaking):
            break
        default:
            Issue.record("expected processing/speaking, got \(sm.currentState)")
        }
    }

    @Test func handleUtteranceOutOfRangeOrdinalFallsThroughToMiss() async {
        var matcher = ScriptedEntityMatcher()
        matcher.ordinalForText["the fifth one"] = EntityMatch(
            surface: "fifth", canonical: "5", confidence: 0.9)
        let (sm, controller) = Self.makeController(matcher: matcher)
        Self.enterDisambiguating(sm)

        await controller.handleUtterance("the fifth one",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // Out-of-range ordinal isn't a pick. It also doesn't match a label.
        // Falls through to the miss-counting path → first miss → retry.
        #expect(sm.context.disambiguationFailedAttempts == 1)
        if case .active(.speaking(_, .disambiguate)) = sm.currentState {
            // expected — retry prompt with the followUp re-armed
        } else {
            Issue.record("expected .speaking with .disambiguate followUp")
        }
    }

    // MARK: - handleUtterance — name pick

    @Test func handleUtteranceLastNameSubstringResumes() async {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("jones",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // "jones" is a >2-char word in "Tony Jones"'s label, so candidates[1]
        // is picked and resume(with:) routes through .processing.
        switch sm.currentState {
        case .active(.processing), .active(.speaking):
            break
        default:
            Issue.record("expected processing/speaking, got \(sm.currentState)")
        }
    }

    // MARK: - handleUtterance — retry / bail

    @Test func handleUtteranceFirstMissReprompts() async {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("uh what",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        #expect(sm.context.disambiguationFailedAttempts == 1)
        if case .active(.speaking(let response, .disambiguate(let pending))) = sm.currentState {
            #expect(response.category == .disambiguation)
            #expect(pending.candidates.count == 2)
            #expect(pending.surface == "Tony")
        } else {
            Issue.record("expected .speaking with .disambiguate followUp")
        }
    }

    @Test func handleUtteranceSecondMissBailsToRest() async {
        let (sm, controller) = Self.makeController()
        Self.enterDisambiguating(sm)
        // Prime one prior miss so the next no-match trips the bail branch.
        sm.updateContext { $0.disambiguationFailedAttempts = 1 }
        await controller.handleUtterance("still no",
                                         suspended: Self.suspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // After bail: counter zeroed, followUp routes to rest (preferredRestState .idle).
        #expect(sm.context.disambiguationFailedAttempts == 0)
        if case .active(.speaking(let response, .rest(let rest))) = sm.currentState {
            #expect(response.text == ResponseTemplateRegistry.disambiguationExit)
            #expect(rest == .idle)
        } else {
            Issue.record("expected .speaking with .rest followUp, got \(sm.currentState)")
        }
    }
}
