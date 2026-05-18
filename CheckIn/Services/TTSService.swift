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
/// The synthesizer reuses the audio session `SpeechService` configures
/// (`.playAndRecord` / `.voiceChat`) so listening and speaking share one
/// full-duplex session. We do not reconfigure it here.
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
