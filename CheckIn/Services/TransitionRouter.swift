// TransitionRouter.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Pure mapping from a state-machine transition to the list of side
/// effects the coordinator should fire. Has no service dependencies and
/// no state of its own — the same `(from, to, preferredRestState)` triple
/// always produces the same effect list. This is what makes the
/// transition table directly unit-testable: tests assert the returned
/// `[TransitionSideEffect]` rather than poking real audio/speech/TTS
/// services.
///
/// Also handles the speaking-state exit: when a `.finished` / `.cancelled`
/// TTS event arrives, `nextStateAfterSpeaking(_:)` produces the right
/// follow-up state from the `SpeakingFollowUp` payload.
struct TransitionRouter {

    /// Side effects produced by a transition, in the order the coordinator
    /// should apply them. Order matters: TTS stops before the audio
    /// session swaps, recognizer cancels before the rest entry, earcons
    /// fire last under the now-correct phase.
    enum SideEffect: Equatable {
        case configureAudio(AudioSessionController.Phase)
        case speak(SpokenResponse)
        case stopTTSIfSpeaking
        case beginListening
        case stopListening
        case cancelListening
        case cancelListeningIfActive
        case playEarcon(Earcon)
        case resetDisambigFailedAttempts
    }

    /// Walk the same five buckets the original `handle(_ event:)` switch
    /// walked, in the same order, and emit side effects rather than
    /// calling services directly. The coordinator dispatches the result.
    func sideEffects(from: DialogState,
                     to: DialogState,
                     preferredRestState: RestState) -> [SideEffect] {
        var effects: [SideEffect] = []

        // Bucket 1: speaking-state side effects run first so the synth
        // is stopped cleanly ahead of any session category swap.
        switch (from, to) {
        case (_, .active(.speaking(let response, _))):
            effects.append(.configureAudio(.speaking))
            effects.append(.speak(response))
        case (.active(.speaking), _):
            effects.append(.stopTTSIfSpeaking)
        default:
            break
        }

        // Bucket 2: recognizer lifecycle.
        switch (from, to) {
        case (.active(.idle), .active(.listening)),
             (.active(.speaking), .active(.listening)),
             (.active(.disambiguating), .active(.listening)):
            // Speech service's startListening tears down any in-flight
            // recognizer internally, so the conversation-mode case of
            // .disambiguating → .listening doesn't need an explicit cancel.
            effects.append(.beginListening)
        case (.active(.speaking), .active(.disambiguating)):
            // Auto-listen for the disambig answer in conversation mode
            // only. Tap-to-talk leaves the recognizer off; the panel
            // re-arms it on candidate tap or mic-press.
            if preferredRestState == .listening {
                effects.append(.beginListening)
            }
        case (.active(.disambiguating), _):
            // Conversation mode left the recognizer running; tap-to-talk
            // didn't. Guard so the cancel is a no-op when nothing's live.
            effects.append(.cancelListeningIfActive)
        case (.active(.listening), .active(.processing)):
            // User signaled done — finalize so the final transcript fires.
            effects.append(.stopListening)
        case (.active(.listening), _):
            // Any other exit from listening is a cancel — discard the partial.
            effects.append(.cancelListening)
        default:
            break
        }

        // Bucket 3: audio session deactivation on entry to rest states
        // that hold no mic.
        switch to {
        case .active(.idle), .active(.helpDisplayed), .active(.settingsDisplayed):
            effects.append(.configureAudio(.inactive))
        default:
            break
        }

        // Bucket 4: rest-entry housekeeping — zero the disambig miss
        // counter so it can't leak into the next turn.
        switch to {
        case .active(.idle), .active(.listening):
            effects.append(.resetDisambigFailedAttempts)
        default:
            break
        }

        // Bucket 5: earcons fire on entry to a state category, not on
        // intra-category transitions (processing(.thinking) shifting to
        // processing(.speakingPlaceholder) is one processing visit, not
        // two).
        if isListening(to) && !isListening(from) {
            effects.append(.playEarcon(.listening))
        }
        if isProcessing(to) && !isProcessing(from) {
            effects.append(.playEarcon(.thinking))
        }

        return effects
    }

    /// Map a finished/cancelled `.speaking` state to the state machine's
    /// next destination, driven by the `SpeakingFollowUp` payload. Returns
    /// nil when the current state isn't `.speaking` (the TTS event
    /// arrived after some other transition already moved the machine).
    func nextStateAfterSpeaking(_ state: DialogState) -> DialogState? {
        guard case .active(.speaking(_, let followUp)) = state else { return nil }
        switch followUp {
        case .rest(let restState):
            switch restState {
            case .idle: return .active(.idle)
            case .listening: return .active(.listening)
            }
        case .disambiguate(let pending):
            return .active(.disambiguating(
                suspendedIntent: pending.suspendedIntent,
                candidates: pending.candidates,
                surface: pending.surface
            ))
        }
    }

    private func isListening(_ state: DialogState) -> Bool {
        if case .active(.listening) = state { return true }
        return false
    }

    private func isProcessing(_ state: DialogState) -> Bool {
        if case .active(.processing) = state { return true }
        return false
    }
}
