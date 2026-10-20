// GraphText.swift
// BlickGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// A light HTML-to-text reduction for the short Teams chat bodies the watch
/// shows: block tags become line breaks, other tags are dropped, and the common
/// entities are decoded. Email bodies are not run through it; Graph returns
/// those as plain text on request.
public func plainText(fromHTML html: String) -> String {
    var text = html
    for pattern in ["<style[^>]*>.*?</style>", "<script[^>]*>.*?</script>"] {
        text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }
    text = text.replacingOccurrences(of: "<br\\s*/?>|</(p|div|li|tr|h[1-6])>", with: "\n", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = decodeEntities(text)
    text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: " ?\\n ?", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func decodeEntities(_ text: String) -> String {
    let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'"]
    var result = text
    for (entity, character) in named {
        result = result.replacingOccurrences(of: entity, with: character)
    }
    result = replaceNumericEntities(in: result)
    return result.replacingOccurrences(of: "&amp;", with: "&")
}

private func replaceNumericEntities(in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") else { return text }
    var result = text
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
    for match in matches {
        guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result) else { continue }
        let body = result[digits]
        let value = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
        guard let value, let scalar = Unicode.Scalar(value) else { continue }
        result.replaceSubrange(whole, with: String(Character(scalar)))
    }
    return result
}
