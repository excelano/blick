// PendingMutation.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// What a pending mutation will do once the user confirms. Single-target
/// variants act on one message ID; bulk variants act on the array. The
/// distinction matters for the confirmation prompt (count-aware phrasing)
/// and for the executor (single PATCH vs filter-collect-iterate).
enum MutationKind: Equatable {
    case markRead
    case flag
    case delete
    case bulkMarkRead
    case bulkFlag
    case bulkDelete
}

/// A user request waiting on yes/no. Carried in `.active(.confirming(_))`
/// while the user decides, and in `SpeakingFollowUp.confirm(_)` while the
/// prompt is being spoken. Once confirmed, the executor uses `targets` to
/// drive Graph PATCHes; `description` is the speakable verb-phrase used by
/// the prompt template and the success announcement so phrasing stays
/// consistent across the three surfaces (prompt, screen, ack).
struct PendingMutation: Equatable {
    let kind: MutationKind
    let targets: [String]
    let description: String
}
