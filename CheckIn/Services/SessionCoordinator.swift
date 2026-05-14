// SessionCoordinator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Translates `StateMachine` transitions into service side effects. The
/// state machine stays free of service dependencies; the coordinator owns
/// the consequence side: start the recognizer on entry to listening, stop
/// the synthesizer on exit from speaking, fetch the summary on entry to
/// active, and so on.
///
/// Phase 5 mic-only slice: the coordinator logs every transition and
/// (in a later slice) drives `SpeechService.startListening` / `cancel`.
/// Phase 6 onward adds TTS, GraphClient, and intent routing dispatch.
@MainActor
final class SessionCoordinator {
    private let stateMachine: StateMachine
    private let speechService: any SpeechService

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?

    init(stateMachine: StateMachine, speechService: any SpeechService) {
        self.stateMachine = stateMachine
        self.speechService = speechService
    }

    /// Begin consuming the state machine's transition stream. Idempotent so
    /// SwiftUI's `.task` modifier firing twice during view reattachment
    /// doesn't spawn duplicate consumers.
    func start() {
        guard transitionTask == nil else { return }
        let stream = stateMachine.transitions
        transitionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.handle(event)
            }
        }
    }

    func stop() {
        transitionTask?.cancel()
        transitionTask = nil
    }

    private func handle(_ event: TransitionEvent) async {
        logger.debug("saw: \(String(describing: event.from)) -> \(String(describing: event.to))")
        // Phase 5 scaffold: mirror to stdout so `devicectl process launch
        // --console` shows transitions over SSH. Remove once we have a
        // device-side `os_log` streaming path that survives SSH.
        print("[coordinator] \(event.from) -> \(event.to)")
    }
}
