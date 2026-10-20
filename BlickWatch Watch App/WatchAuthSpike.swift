// WatchAuthSpike.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if DEBUG
import BlickKit
import SwiftUI

struct WatchAuthSpikeView: View {
    private let relay = WatchSignInRelay.shared
    @State private var lines: [String] = []
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in from Settings on the iPhone.").font(.caption2)
                if !relay.status.isEmpty { Text(relay.status).font(.caption2) }
                Button("Get token") { run { _ = try await WatchTokenProvider.shared.graphAccessToken(); lines.append("ok: access token") } }
                Button("Fetch snapshot") { run { try await fetchSnapshot() } }
                Button("Forget", role: .destructive) { run { await WatchTokenProvider.shared.signOut(); lines.append("signed out") } }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2)
                }
            }
        }
        .disabled(working)
        .navigationTitle("Standalone")
    }

    private func run(_ step: @escaping () async throws -> Void) {
        working = true
        Task {
            do { try await step() } catch { lines.append("FAILED: \(error.localizedDescription)") }
            working = false
        }
    }

    private func fetchSnapshot() async throws {
        let snapshot = try await WatchStandalone.snapshot()
        lines.append("mail \(snapshot.unreadEmailCount), chat \(snapshot.chatCount), presence \(snapshot.presence.rawValue)")
        lines.append("lists: \(snapshot.topEmails.count) mail, \(snapshot.topChats.count) chat")
        lines.append("next: \(snapshot.nextMeetingSubject ?? "none")")
    }
}
#endif
