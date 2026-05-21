// Interpreter.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Parses a transcript into a `Command` the executor can run. The seam
/// lets the implementation grow from a literal phrase table to pattern
/// matching to embeddings without disturbing the executor or domain
/// layers. Returns `nil` for unrecognized input — the caller decides
/// whether to refuse, prompt, or fall back to the legacy voice path.
protocol Interpreter {
    func interpret(_ text: String) -> Command?
}

/// Initial implementation: a literal lookup against a small, hand-listed
/// set of phrasings. Trivial to extend, trivial to test. Phrases are
/// normalized (lowercased, trimmed) before matching so common
/// recognizer artifacts don't miss the table.
struct PhraseInterpreter: Interpreter {

    func interpret(_ text: String) -> Command? {
        let normalized = normalize(text)
        switch normalized {
        case "refresh", "check", "check again":
            return .refresh
        default:
            return nil
        }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
