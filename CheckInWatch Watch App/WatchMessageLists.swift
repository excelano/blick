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

    private var emails: [SnapshotEmail] { receiver.snapshot?.topEmails ?? [] }

    var body: some View {
        List {
            if emails.isEmpty {
                Text("No unread mail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(emails) { email in
                    NavigationLink {
                        WatchEmailReaderView(receiver: receiver, email: email)
                    } label: {
                        emailRow(email)
                    }
                }
            }
        }
        .navigationTitle("Email")
    }

    private func emailRow(_ email: SnapshotEmail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(email.sender)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(email.subject)
                .font(.caption2)
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

/// The watch's pending-chat list, reached from the chat chip.
struct WatchChatListView: View {
    let receiver: WatchSessionReceiver

    private var chats: [SnapshotChat] { receiver.snapshot?.topChats ?? [] }

    var body: some View {
        List {
            if chats.isEmpty {
                Text("No pending chats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chats) { chat in
                    NavigationLink {
                        WatchChatReaderView(receiver: receiver, chat: chat)
                    } label: {
                        chatRow(chat)
                    }
                }
            }
        }
        .navigationTitle("Chats")
    }

    private func chatRow(_ chat: SnapshotChat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.sender)
                .font(.caption.weight(.semibold))
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

/// Reads a single email on the wrist. Shows the snapshot preview immediately,
/// then asks the phone for the full body and swaps it in. If the phone can't be
/// reached the preview stays with a quiet "open on iPhone" note. Slice 4 marks
/// the message read on open.
struct WatchEmailReaderView: View {
    let receiver: WatchSessionReceiver
    let email: SnapshotEmail
    @State private var fullBody: String?
    @State private var loaded = false

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
    }
}

/// Reads a chat thread on the wrist. Preview first, then the recent transcript
/// relayed from the phone; same phone-unreachable fallback as the email reader.
struct WatchChatReaderView: View {
    let receiver: WatchSessionReceiver
    let chat: SnapshotChat
    @State private var thread: String?
    @State private var loaded = false

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
