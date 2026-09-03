// MailFolder.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// A destination the user can file a message into. Flattened for the picker:
/// Graph returns folders as a tree, but a list indented by `depth` is easier
/// to scan and to render than a nested outline, and mail hierarchies here are
/// shallow in practice.
struct MailFolder: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// 0 for a top-level folder, 1 for a child of one. The picker indents by
    /// this rather than nesting rows.
    let depth: Int
}

/// Graph's well-known folder names, accepted anywhere a folder id is taken.
/// Using the well-known name avoids a lookup round-trip for the three
/// destinations Blick moves mail to without asking.
enum WellKnownFolder {
    static let inbox = "inbox"
    static let archive = "archive"
    /// Where Graph's own `DELETE /me/messages/{id}` puts a message. Blick
    /// moves messages here explicitly instead of calling DELETE, because
    /// `/move` returns the relocated message and DELETE returns nothing —
    /// and without the new id there is no way to move it back for an undo.
    static let deletedItems = "deleteditems"
}
