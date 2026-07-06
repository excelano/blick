// EmailListView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The full email screen, reached by tapping the summary's Email header. With
/// an empty search field it shows the same unread list the summary holds; typing
/// runs a Graph `$search` across the whole mailbox (all folders, read and
/// unread) and shows the results. A row opens the existing preview sheet.
///
/// Search is debounced and guarded by a generation counter so a slow lookup
/// can't land after a newer keystroke has moved on — the source is the network,
/// so unlike the composer's local type-ahead this race is real.
struct EmailListView: View {
    var inbox: Inbox
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [Email] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    /// Bumped on every keystroke; a search only applies its result when its
    /// generation is still current, so stale responses are dropped.
    @State private var generation = 0
    @State private var previewTarget: MessagePreviewTarget?
    /// The browse list shown with an empty search field: the recent inbox,
    /// read and unread. Seeded instantly from the unread summary, then replaced
    /// by the full fetch.
    @State private var inboxEmails: [Email] = []
    @State private var inboxLoaded = false
    @State private var inboxFailed = false
    /// The id of the row whose preview is open, so its read state can be synced
    /// when the sheet closes (the preview auto-marks read on the server).
    @State private var openedId: String?

    private var isSearchActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearchActive {
                    BrowseListContent(items: results, isLoading: isSearching, failed: searchFailed,
                                      failedText: "Couldn't search. Check your connection and try again.",
                                      emptyText: "No messages found.") { emailList($0) }
                } else {
                    BrowseListContent(items: inboxEmails, isLoading: !inboxLoaded, failed: inboxFailed,
                                      failedText: "Couldn't load your inbox. Check your connection and try again.",
                                      emptyText: "Your inbox is empty.") { emailList($0) }
                }
            }
            .browseListChrome(title: "Email", onClose: onClose)
        }
        .searchable(text: $query, prompt: "Search all mail")
        .onChange(of: query) { _, newValue in
            Task { await runSearch(newValue) }
        }
        .task { await loadInbox() }
        .preferredColorScheme(.dark)
        .messagePreviewSheet(inbox: inbox, target: $previewTarget, onDismiss: markOpenedRead)
    }

    private func loadInbox() async {
        do {
            inboxEmails = try await inbox.recentInbox()
            inboxLoaded = true
        } catch {
            inboxFailed = true
        }
    }

    private func emailList(_ emails: [Email]) -> some View {
        List {
            ForEach(emails) { email in
                let matchingMeeting = email.isInvite ? inbox.meetingMatching(email) : nil
                EmailRow(
                    email: email,
                    matchingMeeting: matchingMeeting,
                    onTap: { openedId = email.id; previewTarget = .email(email) },
                    onRsvp: { response in
                        if let id = matchingMeeting?.id {
                            Task { await inbox.respondToMeeting(response, meetingId: id) }
                        }
                    },
                    onConflictTap: {}
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { toggleRead(email) } label: {
                        Label(email.isRead ? "Mark Unread" : "Mark Read",
                              systemImage: email.isRead ? "envelope.badge" : "envelope.open")
                    }
                    .tint(email.isRead ? .blue : .green)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { toggleFlag(email) } label: {
                        Label(email.isFlagged ? "Unflag" : "Flag",
                              systemImage: email.isFlagged ? "flag.slash" : "flag")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
    }

    /// Toggle read/unread or flag: flip the row optimistically (it stays put in
    /// a browse list, unlike the summary's unread triage), drive Graph through
    /// the browse-safe Inbox path, and revert the row if that call fails.
    private func toggleRead(_ email: Email) {
        let target = !email.isRead
        updateLocal(email.id) { $0.with(isRead: target) }
        Task {
            do {
                try await inbox.setEmailReadFromBrowse(target, emailId: email.id, wasUnread: !email.isRead)
            } catch {
                updateLocal(email.id) { $0.with(isRead: !target) }
            }
        }
    }

    private func toggleFlag(_ email: Email) {
        let flagged = !email.isFlagged
        updateLocal(email.id) { $0.with(isFlagged: flagged) }
        Task {
            do {
                try await inbox.setEmailFlaggedFromBrowse(flagged, emailId: email.id)
            } catch {
                updateLocal(email.id) { $0.with(isFlagged: !flagged) }
            }
        }
    }

    /// A tapped message is auto-marked read by the preview sheet on the server;
    /// reflect that on the row when the sheet closes so the browse list doesn't
    /// keep showing it unread.
    private func markOpenedRead() {
        guard let id = openedId else { return }
        openedId = nil
        updateLocal(id) { $0.with(isRead: true) }
    }

    private func updateLocal(_ id: String, _ transform: (Email) -> Email) {
        if let i = inboxEmails.firstIndex(where: { $0.id == id }) { inboxEmails[i] = transform(inboxEmails[i]) }
        if let i = results.firstIndex(where: { $0.id == id }) { results[i] = transform(results[i]) }
    }

    private func runSearch(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        let mine = generation
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            searchFailed = false
            return
        }
        isSearching = true
        searchFailed = false
        // Debounce: wait out a burst of keystrokes, bail if superseded.
        try? await Task.sleep(for: .milliseconds(300))
        guard mine == generation else { return }
        do {
            let found = try await inbox.searchEmails(trimmed)
            guard mine == generation else { return }
            results = found
            isSearching = false
        } catch {
            guard mine == generation else { return }
            searchFailed = true
            isSearching = false
        }
    }
}
