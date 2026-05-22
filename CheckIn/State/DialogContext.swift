// DialogContext.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Per-session dialog state held alongside the state machine. Memory only;
/// nothing persists to disk.
struct DialogContext {
    var summary: CheckInSummary?
}
