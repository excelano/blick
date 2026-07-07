// WatchMessageLists.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The watch's unread-mail list, reached by tapping the envelope chip on the
/// glance. Rows come straight from the pushed snapshot (sender, subject, a
/// preview line) — no Graph call here. Tapping a row opens the reader, which
/// asks the phone for the full body.
struct WatchEmailListView: View {
    let receiver: WatchSessionReceiver
    @State private var extended: [SnapshotEmail]?
    @State private var loadingMore = false
    @State private var loadFailed = false

    private var pushed: [SnapshotEmail] { receiver.snapshot?.topEmails ?? [] }
    /// The unread front until the user loads more, then the recent inbox
    /// (read + unread) the phone relayed.
    private var displayed: [SnapshotEmail] { extended ?? pushed }

    var body: some View {
        List {
            if displayed.isEmpty {
                Text("No unread mail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayed) { email in
                    NavigationLink {
                        WatchEmailReaderView(receiver: receiver, email: email)
                    } label: {
                        emailRow(email)
                    }
                }
            }
            LoadMoreRow(
                hidden: extended != nil,
                loading: loadingMore,
                failed: loadFailed,
                action: { Task { await loadMore() } }
            )
        }
        .navigationTitle("Email")
    }

    private func loadMore() async {
        loadingMore = true
        loadFailed = false
        let more = await receiver.requestMoreEmails()
        loadingMore = false
        if let more {
            extended = more
        } else {
            loadFailed = true
        }
    }

    private func emailRow(_ email: SnapshotEmail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(email.sender)
                .font(.caption.weight(email.isRead ? .regular : .semibold))
                .lineLimit(1)
            Text(email.subject)
                .font(.caption2)
                .foregroundStyle(email.isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            if !email.preview.isEmpty {
                Text(email.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The watch's unread-chat list, reached from the chat chip.
struct WatchChatListView: View {
    let receiver: WatchSessionReceiver
    @State private var extended: [SnapshotChat]?
    @State private var loadingMore = false
    @State private var loadFailed = false

    private var pushed: [SnapshotChat] { receiver.snapshot?.topChats ?? [] }
    private var displayed: [SnapshotChat] { extended ?? pushed }

    var body: some View {
        List {
            if displayed.isEmpty {
                Text("No unread chats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayed) { chat in
                    NavigationLink {
                        WatchChatReaderView(receiver: receiver, chat: chat)
                    } label: {
                        chatRow(chat)
                    }
                }
            }
            LoadMoreRow(
                hidden: extended != nil,
                loading: loadingMore,
                failed: loadFailed,
                action: { Task { await loadMore() } }
            )
        }
        .navigationTitle("Chats")
    }

    private func loadMore() async {
        loadingMore = true
        loadFailed = false
        let more = await receiver.requestMoreChats()
        loadingMore = false
        if let more {
            extended = more
        } else {
            loadFailed = true
        }
    }

    private func chatRow(_ chat: SnapshotChat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.sender)
                .font(.caption.weight(chat.isRead ? .regular : .semibold))
                .lineLimit(1)
            if !chat.preview.isEmpty {
                Text(chat.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// The "Load more" affordance at the foot of a watch list — pulls the recent
/// inbox (read + unread) from the phone on demand, so the wrist can browse
/// deeper than the pushed unread front without a separate screen. Disappears
/// once the deeper set is loaded.
private struct LoadMoreRow: View {
    let hidden: Bool
    let loading: Bool
    let failed: Bool
    let action: () -> Void

    var body: some View {
        if !hidden {
            Button(action: action) {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Load more", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(loading)
            if failed {
                Text("Couldn't load — open iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Reads a single email on the wrist. Shows the snapshot preview immediately,
/// then asks the phone for the full body and swaps it in. If the phone can't be
/// reached the preview stays with a quiet "open on iPhone" note. Opening marks
/// the message read; the action row below relays reply / flag / mark-unread.
struct WatchEmailReaderView: View {
    let receiver: WatchSessionReceiver
    let email: SnapshotEmail
    @Environment(\.dismiss) private var dismiss
    @State private var fullBody: String?
    @State private var loaded = false
    @State private var isFlagged: Bool
    @State private var showReply = false

    init(receiver: WatchSessionReceiver, email: SnapshotEmail) {
        self.receiver = receiver
        self.email = email
        _isFlagged = State(initialValue: email.isFlagged)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(email.subject)
                    .font(.caption.weight(.semibold))
                    .lineLimit(3)
                Text(email.sender)
                    .font(.caption2)
                    .foregroundStyle(Brand.accent)
                Text(email.received.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                Text(fullBody ?? email.preview)
                    .font(.caption)
                MessageBodyStatus(loaded: loaded, haveFullBody: fullBody != nil)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Email")
        .task {
            // Opening it is reading it — tell the phone, then load the body.
            receiver.sendMarkEmailRead(id: email.id)
            fullBody = await receiver.requestEmailBody(id: email.id)
            loaded = true
        }
        .sheet(isPresented: $showReply) {
            WatchReplyView(receiver: receiver, target: .email(email.id))
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button { showReply = true } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
                    .frame(maxWidth: .infinity)
            }
            Button { toggleFlag() } label: {
                Label(isFlagged ? "Unflag" : "Flag", systemImage: isFlagged ? "flag.slash" : "flag")
                    .frame(maxWidth: .infinity)
            }
            Button { markUnread() } label: {
                Label("Mark Unread", systemImage: "envelope.badge")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }

    private func toggleFlag() {
        isFlagged.toggle()
        receiver.sendSetEmailFlag(id: email.id, flagged: isFlagged)
    }

    private func markUnread() {
        receiver.sendMarkEmailUnread(id: email.id)
        dismiss()
    }
}

/// Reads a chat thread on the wrist. Preview first, then the recent transcript
/// relayed from the phone; same phone-unreachable fallback as the email reader.
struct WatchChatReaderView: View {
    let receiver: WatchSessionReceiver
    let chat: SnapshotChat
    @Environment(\.dismiss) private var dismiss
    @State private var thread: String?
    @State private var loaded = false
    @State private var showReply = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(chat.sender)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                Text(chat.sent.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                Text(thread ?? chat.preview)
                    .font(.caption)
                MessageBodyStatus(loaded: loaded, haveFullBody: thread != nil)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Chat")
        .task {
            receiver.sendMarkChatRead(id: chat.id)
            thread = await receiver.requestChatBody(id: chat.id)
            loaded = true
        }
        .sheet(isPresented: $showReply) {
            WatchReplyView(receiver: receiver, target: .chat(chat.id))
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button { showReply = true } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
                    .frame(maxWidth: .infinity)
            }
            Button { markUnread() } label: {
                Label("Mark Unread", systemImage: "message.badge")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }

    private func markUnread() {
        receiver.sendMarkChatUnread(id: chat.id)
        dismiss()
    }
}

/// Where a wrist-composed reply is headed. Same-channel only: an email reply
/// relays reply-all, a chat reply posts into the existing Teams thread.
enum WatchReplyTarget {
    case email(String)
    case chat(String)
}

/// The wrist reply composer. A single `TextField` gives the standard watchOS
/// input surface — scribble, dictation, keyboard, emoji — the same one Messages
/// uses; there are no canned responses. Send relays to the phone and waits for
/// its ack: a real send is never queued silently, so if the phone is out of
/// reach the user is told to open the iPhone rather than left guessing.
struct WatchReplyView: View {
    let receiver: WatchSessionReceiver
    let target: WatchReplyTarget
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Reply", text: $text, axis: .vertical)
                        .lineLimit(1...6)
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Send")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty || sending)
                    if failed {
                        Text("Couldn't send — open iPhone.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Reply")
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() async {
        sending = true
        failed = false
        let ok: Bool
        switch target {
        case .email(let id): ok = await receiver.sendReplyEmail(id: id, text: trimmed)
        case .chat(let id): ok = await receiver.sendReplyChat(id: id, text: trimmed)
        }
        sending = false
        if ok {
            dismiss()
        } else {
            failed = true
        }
    }
}

/// The small footer under a reader body: a spinner while the phone fetch is in
/// flight, or an "open on iPhone" note when it came back empty (phone out of
/// reach), so the preview above never looks like the whole message.
private struct MessageBodyStatus: View {
    let loaded: Bool
    let haveFullBody: Bool

    var body: some View {
        if !loaded {
            ProgressView()
                .controlSize(.mini)
                .padding(.top, 4)
        } else if !haveFullBody {
            Text("Open on iPhone for the full message.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}
