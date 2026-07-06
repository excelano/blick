// EmailAddressValidation.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Pure validation and parsing for user-typed email recipients. The compose
/// surface lets you type addresses directly (and pick from Contacts), so we
/// need one place that decides what counts as a sendable SMTP address and how
/// to split a free-typed line into individual recipients. No network, no UI —
/// unit-testable in isolation. The bar is deliberately lenient: we reject the
/// obviously-broken (missing `@`, empty parts, no dot in the domain) and let
/// Graph make the final call on delivery.
public enum EmailAddressValidation {

    /// Trim surrounding whitespace and strip a `Display Name <addr>` wrapper
    /// down to the bare address, then check it has the minimal shape of an
    /// SMTP address. Returns the cleaned address, or nil if it doesn't
    /// qualify. Case is preserved (the local part can be case-sensitive).
    public static func normalized(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unwrap a "Name <addr>" form to the address inside the angle brackets.
        if let open = candidate.lastIndex(of: "<"),
           let close = candidate.lastIndex(of: ">"),
           open < close {
            let inner = candidate[candidate.index(after: open)..<close]
            candidate = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return isValid(candidate) ? candidate : nil
    }

    /// True when `address` has the minimal shape of a deliverable SMTP
    /// address: exactly one `@`, a non-empty local part, and a domain with a
    /// dot and no leading/trailing dot. Assumes `address` is already trimmed.
    public static func isValid(_ address: String) -> Bool {
        guard !address.contains(where: { $0 == " " }) else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard domain.contains("."),
              !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return true
    }

    /// Split a free-typed recipient line on comma / semicolon / newline and
    /// normalize each piece. Whitespace is NOT a separator so a pasted
    /// `Display Name <addr>` survives intact for the angle-bracket unwrap.
    /// Returns the valid addresses (order preserved, de-duplicated
    /// case-insensitively) and the raw pieces that failed to validate, so the
    /// UI can flag them.
    public static func parseList(_ raw: String) -> (valid: [String], invalid: [String]) {
        let separators = CharacterSet(charactersIn: ",;\n\r")
        let pieces = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var valid: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()
        for piece in pieces {
            guard let clean = normalized(piece) else {
                invalid.append(piece)
                continue
            }
            let key = clean.lowercased()
            if seen.insert(key).inserted {
                valid.append(clean)
            }
        }
        return (valid, invalid)
    }
}
