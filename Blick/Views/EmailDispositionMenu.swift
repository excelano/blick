// EmailDispositionMenu.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Archive / Move / Delete, shared by every surface that lists or shows a
/// message: the summary's email rows, the browse list, and the preview sheet.
/// Extracted from the start rather than inlined on one screen, because the
/// meeting context menu taught that the second caller always arrives.
///
/// `onMove` is a closure because the destination picker is a sheet and each
/// screen presents its own; this only reports which message the user wants to
/// file. `onDisposed` fires once the message has actually left the Inbox, so
/// a screen can drop its own copy of the row (the browse list) or dismiss
/// itself (the preview sheet) — the shared summary state is already updated
/// by `Inbox`, but these surfaces hold their own.
///
/// Delete is offered here and never as a swipe. Swipe already carries
/// mark-read one way and flag the other, and reworking that to free a slot
/// would trade a well-understood gesture for a mis-swipe that files mail. The
/// menu costs one tap and removes the whole class of accident. It is safe to
/// offer without a confirmation dialog because it is a move to Deleted Items,
/// recoverable both from the undo banner and from Outlook.
@MainActor
@ViewBuilder
func emailDispositionMenu(for email: Email,
                          inbox: Inbox,
                          onMove: @escaping (Email) -> Void,
                          onDisposed: @escaping () -> Void = {}) -> some View {
    Button {
        Task { await inbox.archiveEmail(email); onDisposed() }
    } label: {
        Label("Archive", systemImage: "archivebox")
    }
    Button {
        onMove(email)
    } label: {
        Label("Move to…", systemImage: "folder")
    }
    Button(role: .destructive) {
        Task { await inbox.deleteEmail(email); onDisposed() }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
