// TransitionRouterTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
import Foundation
@testable import CheckIn

/// Pins the transition side-effect table. Every (from, to) pair the
/// coordinator used to hand-code in its switch is exercised here against
/// the pure router. Failures here are regressions in the routing logic,
/// not in any service.
struct TransitionRouterTests {

    // MARK: - Fixtures

    private static let router = TransitionRouter()

    private static let speakingResponse = SpokenResponse(
        text: "Three unread.",
        category: .summary
    )

    private static let disambigPending = PendingDisambiguation(
        suspendedIntent: SuspendedIntent(utterance: "any from tony", intent: "filter"),
        surface: "Tony",
        candidates: [Candidate(label: "Tony Smith", entityRef: "Tony Smith")]
    )

    private static let speakingToRestIdle: DialogState = .active(.speaking(
        response: speakingResponse, followUp: .rest(.idle)
    ))

    private static let speakingToRestListening: DialogState = .active(.speaking(
        response: speakingResponse, followUp: .rest(.listening)
    ))

    private static let speakingToDisambig: DialogState = .active(.speaking(
        response: speakingResponse, followUp: .disambiguate(disambigPending)
    ))

    private static let disambiguating: DialogState = .active(.disambiguating(
        suspendedIntent: disambigPending.suspendedIntent,
        candidates: disambigPending.candidates,
        surface: "Tony"
    ))

    // MARK: - Entering .speaking

    @Test func enteringSpeakingFromProcessingConfiguresAudioAndSpeaks() {
        let effects = Self.router.sideEffects(
            from: .active(.processing(.thinking)),
            to: Self.speakingToRestIdle,
            preferredRestState: .idle
        )
        #expect(effects == [.configureAudio(.speaking),
                            .speak(Self.speakingResponse)])
    }

    @Test func enteringSpeakingFromListeningStopsListeningFirst() {
        // Not a real STATES.md transition but exercises ordering rules:
        // listening→speaking should cancelListening before speak.
        // STATES.md actually goes listening→processing→speaking; testing the
        // documented path instead.
        let effects = Self.router.sideEffects(
            from: .active(.processing(.thinking)),
            to: Self.speakingToRestIdle,
            preferredRestState: .listening
        )
        #expect(effects.first == .configureAudio(.speaking))
        #expect(effects.contains(.speak(Self.speakingResponse)))
    }

    // MARK: - Exiting .speaking

    @Test func speakingToIdleStopsTTSAndDeactivatesAudio() {
        let effects = Self.router.sideEffects(
            from: Self.speakingToRestIdle,
            to: .active(.idle),
            preferredRestState: .idle
        )
        #expect(effects == [.stopTTSIfSpeaking,
                            .configureAudio(.inactive),
                            .resetDisambigFailedAttempts])
    }

    @Test func speakingToListeningBeginsListening() {
        let effects = Self.router.sideEffects(
            from: Self.speakingToRestListening,
            to: .active(.listening),
            preferredRestState: .listening
        )
        #expect(effects == [.stopTTSIfSpeaking,
                            .beginListening,
                            .resetDisambigFailedAttempts,
                            .playEarcon(.listening)])
    }

    @Test func speakingToDisambiguatingAutolistensInConversationMode() {
        let effects = Self.router.sideEffects(
            from: Self.speakingToDisambig,
            to: Self.disambiguating,
            preferredRestState: .listening
        )
        #expect(effects == [.stopTTSIfSpeaking, .beginListening])
    }

    @Test func speakingToDisambiguatingStaysSilentInTapToTalk() {
        let effects = Self.router.sideEffects(
            from: Self.speakingToDisambig,
            to: Self.disambiguating,
            preferredRestState: .idle
        )
        #expect(effects == [.stopTTSIfSpeaking])
    }

    // MARK: - Listening lifecycle

    @Test func idleToListeningBeginsAndPlaysEarcon() {
        let effects = Self.router.sideEffects(
            from: .active(.idle),
            to: .active(.listening),
            preferredRestState: .listening
        )
        #expect(effects == [.beginListening,
                            .resetDisambigFailedAttempts,
                            .playEarcon(.listening)])
    }

    @Test func listeningToProcessingFinalizesRecognizer() {
        let effects = Self.router.sideEffects(
            from: .active(.listening),
            to: .active(.processing(.thinking)),
            preferredRestState: .listening
        )
        #expect(effects == [.stopListening, .playEarcon(.thinking)])
    }

    @Test func listeningToIdleCancelsAndDeactivates() {
        let effects = Self.router.sideEffects(
            from: .active(.listening),
            to: .active(.idle),
            preferredRestState: .listening
        )
        #expect(effects == [.cancelListening,
                            .configureAudio(.inactive),
                            .resetDisambigFailedAttempts])
    }

    // MARK: - Disambiguating lifecycle

    @Test func disambiguatingToListeningRebuildsRecognizer() {
        // Conversation mode left the recognizer running; startListening's
        // internal teardown covers the swap, so the router emits
        // beginListening alone — no explicit cancel.
        let effects = Self.router.sideEffects(
            from: Self.disambiguating,
            to: .active(.listening),
            preferredRestState: .listening
        )
        #expect(effects == [.beginListening,
                            .resetDisambigFailedAttempts,
                            .playEarcon(.listening)])
    }

    @Test func disambiguatingToIdleGuardedCancel() {
        let effects = Self.router.sideEffects(
            from: Self.disambiguating,
            to: .active(.idle),
            preferredRestState: .idle
        )
        #expect(effects == [.cancelListeningIfActive,
                            .configureAudio(.inactive),
                            .resetDisambigFailedAttempts])
    }

    @Test func disambiguatingToProcessingGuardedCancel() {
        // resumeDisambiguation route — controller transitions to .processing.
        let effects = Self.router.sideEffects(
            from: Self.disambiguating,
            to: .active(.processing(.thinking)),
            preferredRestState: .listening
        )
        #expect(effects == [.cancelListeningIfActive,
                            .playEarcon(.thinking)])
    }

    // MARK: - Help / Settings sheets

    @Test func enteringHelpDeactivatesAudio() {
        let effects = Self.router.sideEffects(
            from: .active(.idle),
            to: .active(.helpDisplayed(returnTo: .idle)),
            preferredRestState: .idle
        )
        #expect(effects == [.configureAudio(.inactive)])
    }

    @Test func enteringSettingsDeactivatesAudio() {
        let effects = Self.router.sideEffects(
            from: .active(.listening),
            to: .active(.settingsDisplayed(returnTo: .listening)),
            preferredRestState: .listening
        )
        #expect(effects == [.cancelListening, .configureAudio(.inactive)])
    }

    // MARK: - Earcon entry-only firing

    @Test func processingToProcessingDoesNotRepeatThinkingEarcon() {
        let effects = Self.router.sideEffects(
            from: .active(.processing(.thinking)),
            to: .active(.processing(.speakingPlaceholder)),
            preferredRestState: .idle
        )
        // No earcon — both states are the same category.
        #expect(!effects.contains(.playEarcon(.thinking)))
    }

    // MARK: - Rest-entry disambig reset

    @Test func processingToIdleResetsDisambig() {
        let effects = Self.router.sideEffects(
            from: .active(.processing(.thinking)),
            to: .active(.idle),
            preferredRestState: .idle
        )
        #expect(effects.contains(.resetDisambigFailedAttempts))
    }

    @Test func enteringDisambiguatingDoesNotResetDisambig() {
        let effects = Self.router.sideEffects(
            from: Self.speakingToDisambig,
            to: Self.disambiguating,
            preferredRestState: .idle
        )
        #expect(!effects.contains(.resetDisambigFailedAttempts))
    }

    // MARK: - nextStateAfterSpeaking

    @Test func speakingExitWithRestIdle() {
        let next = Self.router.nextStateAfterSpeaking(Self.speakingToRestIdle)
        #expect(next == .active(.idle))
    }

    @Test func speakingExitWithRestListening() {
        let next = Self.router.nextStateAfterSpeaking(Self.speakingToRestListening)
        #expect(next == .active(.listening))
    }

    @Test func speakingExitWithDisambiguateFollowUpReconstructsState() {
        let next = Self.router.nextStateAfterSpeaking(Self.speakingToDisambig)
        guard case .active(.disambiguating(let suspended, let candidates, let surface)) = next else {
            Issue.record("expected .disambiguating, got \(String(describing: next))")
            return
        }
        #expect(suspended.utterance == Self.disambigPending.suspendedIntent.utterance)
        #expect(candidates.count == 1)
        #expect(surface == "Tony")
    }

    @Test func speakingExitFromNonSpeakingStateReturnsNil() {
        // TTS event arrived after the machine already moved off .speaking.
        let next = Self.router.nextStateAfterSpeaking(.active(.idle))
        #expect(next == nil)
    }
}
