// StarredSendersView.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickKit
import SwiftUI

/// The management list behind Settings > Starred senders: who is starred,
/// swipe to unstar, and an Add button that opens the same out-of-process
/// contact picker the composer uses, so starring someone who has not mailed
/// recently needs no Contacts permission and no Graph scope.
struct StarredSendersView: View {
    var inbox: Inbox

    @State private var pickingContact = false

    var body: some View {
        Group {
            if inbox.starredSenders.isEmpty {
                MessageListStatus {
                    Text("No starred senders yet. Long-press a message to star its sender, or add someone from Contacts.")
                        .font(.callout)
                        .foregroundStyle(Brand.textMuted)
                        .multilineTextAlignment(.center)
                }
            } else {
                senderList
            }
        }
        .background(Brand.bg)
        .navigationTitle("Starred senders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pickingContact = true
                } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(Brand.accent)
                .accessibilityLabel("Add from Contacts")
            }
        }
        .background {
            // Presented from UIKit, not a nested sheet, for the reason
            // `ContactPicker` documents: its self-dismiss would otherwise
            // cascade into whatever presented it.
            if pickingContact {
                ContactPicker(
                    onPick: { picked in
                        inbox.star(displayName: picked.displayName, address: picked.address)
                        pickingContact = false
                    },
                    onCancel: { pickingContact = false }
                )
            }
        }
    }

    private var senderList: some View {
        List {
            ForEach(inbox.starredSenders) { sender in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sender.displayName)
                        .font(.body)
                        .foregroundStyle(.white)
                    if sender.displayName != sender.address {
                        Text(sender.address)
                            .font(.footnote)
                            .foregroundStyle(Brand.textMuted)
                    }
                }
                .listRowBackground(Brand.bgDarker)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        inbox.unstar(address: sender.address)
                    } label: {
                        Label("Unstar", systemImage: "star.slash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
    }
}
