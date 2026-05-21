// AudioSessionController.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import AVFoundation
import os

/// Single owner of `AVAudioSession` category transitions. Before this lived
/// here, `SpeechService` set `.playAndRecord` on listening and `TTSService`
/// set `.soloAmbient` on speaking, with each side ignorant of the other.
/// Two paths could fight: a tap-mic during TTS swapped category while the
/// synth was mid-utterance, which wedges `AVSpeechSynthesizer` for the rest
/// of the session (Apple's documented gotcha).
///
/// Now the coordinator drives transitions through this controller, calls
/// `configure(for:)` once per phase change, and the per-utterance synth
/// recreation in `AppleTTSService` neutralizes the mid-utterance swap in any
/// path that still slips through.
///
/// Earcons play through `play(_:)` so they fire under whichever category is
/// active for the current phase. That respects silent during speaking
/// (`.soloAmbient`) and bypasses it during listening/disambiguating
/// (`.playAndRecord` — recording-capable categories all bypass by iOS design).
@MainActor
final class AudioSessionController {
    enum Phase: Equatable {
        case listening   // .playAndRecord + .spokenAudio — mic hot, silent bypassed
        case speaking    // .soloAmbient — silent respected
        case inactive    // session deactivated
    }

    private let earconPlayer: any EarconPlayer
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "audio")

    private(set) var currentPhase: Phase = .inactive

    init(earconPlayer: any EarconPlayer) {
        self.earconPlayer = earconPlayer
    }

    /// Move the audio session to the category appropriate for the requested
    /// phase. Idempotent — repeat calls with the same phase are no-ops.
    /// Throws on category-switch or activation failure so the caller can
    /// decide whether to bail (listening: drop back to idle, no mic) or
    /// continue (speaking: the synth still plays under whichever category
    /// stayed active; inactive: cleanup is best-effort).
    func configure(for phase: Phase) throws {
        guard phase != currentPhase else { return }
        let session = AVAudioSession.sharedInstance()
        switch phase {
        case .listening:
            try session.setCategory(.playAndRecord,
                                    mode: .spokenAudio,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        case .speaking:
            try session.setCategory(.soloAmbient)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        case .inactive:
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        currentPhase = phase
        #if DEBUG
        print("[audio] phase=\(phase) category=\(session.category.rawValue) mode=\(session.mode.rawValue)")
        #endif
    }

    /// Play an earcon under the current phase's category. The controller
    /// stays in charge of session state so the earcon never plays under a
    /// stale or unconfigured session.
    func play(_ earcon: Earcon) {
        earconPlayer.play(earcon)
    }
}
