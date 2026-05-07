// HTMLStripper.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Strip HTML tags and decode common entities from a string. Used on Teams chat
/// previews from Microsoft Graph, which sometimes arrive as HTML.
func stripHTML(_ html: String) -> String {
    var s = html

    if let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
        s = styleRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let scriptRegex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
        s = scriptRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    if let commentRegex = try? NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators) {
        s = commentRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    let blockTags = ["</p>", "</div>", "</tr>", "<br>", "<br/>", "<br />"]
    for tag in blockTags {
        s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }

    if let tagRegex = try? NSRegularExpression(pattern: "<[^>]*>") {
        s = tagRegex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ""
        )
    }

    let entities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&nbsp;": " ",
        "&#39;": "'",
        "&quot;": "\"",
        "&apos;": "'"
    ]
    for (entity, replacement) in entities {
        s = s.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }

    if let newlineRegex = try? NSRegularExpression(pattern: "\\n{3,}") {
        s = newlineRegex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n"
        )
    }

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
