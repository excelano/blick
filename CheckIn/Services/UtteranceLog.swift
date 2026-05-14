// UtteranceLog.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Per-turn diagnostic log of classified utterances. Used during the
/// classifier tuning period to capture real recognizer output, the chosen
/// intent, the full ranked candidate list, and the resulting response, so
/// real-world phrasings can drive anchor and threshold adjustments.
///
/// Debug builds wire the concrete `FileUtteranceLog`. Release builds wire
/// `NoOpUtteranceLog` so the diagnostic surface never ships. The protocol
/// stays in both builds; only the file-writing implementation is gated by
/// `#if DEBUG`.
protocol UtteranceLog: AnyObject {
    func record(utterance: String,
                classified: ClassifiedIntent,
                ranking: [IntentRanking],
                response: SpokenResponse) async
}

/// Release-build implementation. The coordinator's record call becomes a
/// dead method invocation that does nothing.
final class NoOpUtteranceLog: UtteranceLog {
    func record(utterance: String,
                classified: ClassifiedIntent,
                ranking: [IntentRanking],
                response: SpokenResponse) async {}
}
