// TTSService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import AVFoundation
import os

/// Text-to-speech surface backing the `speaking` state. The protocol seam
/// lets previews and tests wire a no-op mock without booting
/// `AVSpeechSynthesizer`.
///
/// The real implementation in `AppleTTSService` uses `AVSpeechSynthesizer`
/// with a locale-matched voice (en-GB device gets a British voice), tracks
/// word-boundary callbacks so D8 barge-in can cut cleanly at a word break,
/// and respects the audio session configuration owned by `SpeechService`.
protocol TTSService: AnyObject {
    var isSpeaking: Bool { get }
    var events: AsyncStream<TTSEvent> { get }

    func speak(_ text: String) throws
    func stop()
    func pause()
    func resume()
}

enum TTSEvent: Equatable {
    case started
    case wordBoundary(charIndex: Int)
    case paused
    case resumed
    case finished
    case cancelled
}

enum TTSServiceError: Error {
    case audioSessionUnavailable
    case synthesizerUnavailable
}

/// Apple-backed implementation per the TTSService doc comment.
///
/// `AVSpeechSynthesizer.delegate` is a weak reference, so this class is the
/// delegate directly rather than wrapping one. NSObject inheritance is the
/// minimum needed for `AVSpeechSynthesizerDelegate` conformance.
///
/// Speaking swaps the audio session to `.soloAmbient` before each
/// utterance. `SpeechService` configures `.playAndRecord` for listening,
/// which on iOS always bypasses the silent switch (there's no
/// recording-capable category that doesn't). `.soloAmbient` is the
/// silent-respecting category, so TTS honors the hardware silent switch
/// like Mail/Calendar notifications do. The next mic tap re-sets
/// `.playAndRecord` from `SpeechService`, so the swap is one-way per turn.
final class AppleTTSService: NSObject, TTSService {
    let events: AsyncStream<TTSEvent>
    private let continuation: AsyncStream<TTSEvent>.Continuation

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "tts")

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        let (stream, continuation) = AsyncStream<TTSEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        continuation.finish()
    }

    func speak(_ text: String) throws {
        // Per-phase audio session swap: respect the hardware silent switch
        // during TTS playback. SpeechService's `.playAndRecord` bypasses
        // silent because the recording-capable categories all do; swap to
        // `.soloAmbient` here so a phone set to silent stays silent.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.soloAmbient)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #if DEBUG
            print("[audio] tts category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue)")
            #endif
        } catch {
            logger.error("tts audio session swap failed: \(error.localizedDescription, privacy: .public)")
            // Proceed anyway; the synthesizer can still play under whatever
            // category is active. A logged warning is the right surface.
        }

        let utterance = AVSpeechUtterance(string: text)

        // Voice and rate are read fresh from UserDefaults on every utterance.
        // `@AppStorage` in `SettingsView` writes the same keys; reading here
        // means the next utterance picks up changes without an observer.
        let defaults = UserDefaults.standard
        let voiceIdentifier = defaults.string(forKey: "voiceIdentifier") ?? ""
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        // `UserDefaults.double(forKey:)` returns 0 when the key is absent,
        // which is below `AVSpeechUtteranceMinimumSpeechRate`. Treat 0 as
        // "user hasn't touched the slider yet" and leave the utterance's
        // default rate in place.
        let storedRate = defaults.double(forKey: "speechRate")
        if storedRate > 0 {
            utterance.rate = Float(storedRate)
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        // `.word` cuts at the next word boundary so future D8 barge-in
        // doesn't sound jarring. `.immediate` would chop mid-syllable.
        synthesizer.stopSpeaking(at: .word)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }
}

extension AppleTTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        continuation.yield(.started)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        continuation.yield(.wordBoundary(charIndex: characterRange.location))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didPause utterance: AVSpeechUtterance) {
        continuation.yield(.paused)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didContinue utterance: AVSpeechUtterance) {
        continuation.yield(.resumed)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        continuation.yield(.finished)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        continuation.yield(.cancelled)
    }
}
