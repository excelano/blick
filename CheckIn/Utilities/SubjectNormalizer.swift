// SubjectNormalizer.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

extension String {
    /// Returns a lowercased grouping key for the subject with common
    /// reply/forward prefixes stripped iteratively. So "Re: Re: Fwd:
    /// Status update" and "Status update" both yield "status update".
    /// Used to group emails by topic for the "Mark N with this subject
    /// read" context-menu action.
    var normalizedSubjectKey: String {
        var s = trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["re:", "fwd:", "fw:", "aw:", "sv:"]
        while true {
            let lower = s.lowercased()
            var stripped = false
            for prefix in prefixes where lower.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stripped = true
                break
            }
            if !stripped { break }
        }
        return s.lowercased()
    }
}
