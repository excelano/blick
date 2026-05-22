// HTMLStripper.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// Regexes compiled once at module load. The patterns are static and known
// to be well-formed, so the try? failure path is effectively dead.
private let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators])
private let scriptRegex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators])
private let commentRegex = try? NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)
private let tagRegex = try? NSRegularExpression(pattern: "<[^>]*>")
private let collapseNewlinesRegex = try? NSRegularExpression(pattern: "\\n{3,}")

private let htmlEntities: [String: String] = [
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&nbsp;": " ",
    "&#39;": "'",
    "&quot;": "\"",
    "&apos;": "'"
]

private let blockTags = ["</p>", "</div>", "</tr>", "<br>", "<br/>", "<br />"]

/// Strip HTML tags and decode common entities from a string. Used on Teams chat
/// previews from Microsoft Graph, which sometimes arrive as HTML.
func stripHTML(_ html: String) -> String {
    var s = html

    if let styleRegex {
        s = styleRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let scriptRegex {
        s = scriptRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let commentRegex {
        s = commentRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    for tag in blockTags {
        s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }

    if let tagRegex {
        s = tagRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    for (entity, replacement) in htmlEntities {
        s = s.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }

    if let collapseNewlinesRegex {
        s = collapseNewlinesRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n")
    }

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
