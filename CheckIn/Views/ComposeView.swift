// ComposeView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInGraph
import CheckInKit
import SwiftUI
#if DEBUG
import os
private let log = Logger(subsystem: "com.excelano.checkin", category: "compose")
#endif

/// The one composer for every outgoing message: a new message, a forward, or a
/// reply, across both email and Teams chat. The channel is a dimension chosen
/// during composition (see `Channel`), so a single surface and one recipient
/// model back the whole messaging flow.
///
/// New-message mode shows To (+ Cc / Bcc / Subject in email mode) and a
/// plain-text body, with the Contacts picker on each recipient row. Forward
/// mode shows only To plus an optional note — Graph's `/forward` builds the
/// "Fwd:" subject and quotes the original server-side. Reply mode shows no
/// editable recipients (the recipient is the thread) — just a "Replying to …"
/// context line and the body; same-channel keeps thread semantics, and an
/// email reply can cross to a chat.
///
/// Presented as a standalone `.sheet` (new / forward) or `.inline` inside the
/// preview sheet (reply) — see `Presentation`. On Send success it calls
/// `onSent` if set, else `onClose`; failure surfaces the error inline and
/// leaves everything typed for a retry.
struct ComposeView: View {
    var inbox: Inbox
    /// Dismiss without sending — the Cancel button (sheet) or Back button
    /// (inline reply, returning to the preview underneath).
    let onClose: () -> Void
    /// Called instead of `onClose` after a successful send, when the two must
    /// differ. Reply-in-place uses this: Back returns to the preview, a sent
    /// reply dismisses the whole preview sheet. Nil for the standalone sheets,
    /// where sending and cancelling both just close the sheet.
    let onSent: (() -> Void)?
    var mode: Mode
    let presentation: Presentation

    /// How the composer is hosted. `.sheet` is the standalone full sheet
    /// (new message, forward) with a Cancel button. `.inline` renders inside
    /// the preview sheet in place of its body (reply) with a Back button; the
    /// preview supplies the outer chrome and detents.
    enum Presentation { case sheet, inline }

    enum Mode {
        case newMessage
        /// Forward this message. Carries only what the sheet needs to label
        /// itself and to call `/forward` — the id and the subject.
        case forward(emailId: String, subject: String)
        /// Reply to an email or chat. Same-channel keeps thread semantics
        /// (email `replyAll`, chat post-into-thread); switching channel starts
        /// a fresh message to the sender with a one-line reference. Only
        /// email→chat is available today — a chat carries no sender address to
        /// email back to, which needs a directory-lookup scope we've deferred.
        case reply(Reply)

        /// Everything the reply surface needs, flattened by the caller so the
        /// composer doesn't reach back into the `Email` / `ChatMessage` models.
        struct Reply {
            let source: Channel
            let emailId: String?
            let chatId: String?
            let senderName: String
            /// The email sender's SMTP address, bound as a UPN for a
            /// cross-channel chat. Nil for a chat source (no address on hand).
            let senderAddress: String?
            /// Email subject, prepended as "Re: …" on a cross-channel chat.
            let reference: String
            /// " and N others" for an email reply-all fan-out, else "".
            let emailReplyAllTail: String
            /// " and N others" for a group chat, else "".
            let chatOthersTail: String
        }

        var isForward: Bool {
            if case .forward = self { return true }
            return false
        }

        var isReply: Bool {
            if case .reply = self { return true }
            return false
        }
    }

    /// Which surface the message goes out on. The channel is chosen *during*
    /// composition, not before: the body carries across a flip untouched, and
    /// the email-only fields (Subject, Cc, Bcc) reflow in and out with it.
    /// New compose defaults to `.chat` — the lossless direction to switch
    /// *from*, since every Teams member has an email but not every email
    /// recipient is a Teams user. Forward is email-only and ignores this;
    /// reply defaults to its source channel.
    enum Channel { case chat, email }

    init(inbox: Inbox, onClose: @escaping () -> Void, onSent: (() -> Void)? = nil,
         mode: Mode = .newMessage, presentation: Presentation = .sheet) {
        self.inbox = inbox
        self.onClose = onClose
        self.onSent = onSent
        self.mode = mode
        self.presentation = presentation
        // Reply opens on its source channel; everything else opens on chat.
        let initial: Channel
        if case .reply(let reply) = mode { initial = reply.source } else { initial = .chat }
        _channel = State(initialValue: initial)
    }

    @State private var channel: Channel
    @State private var toText = ""
    @State private var ccText = ""
    @State private var bccText = ""
    @State private var showCcBcc = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Which recipient field a Contacts pick should fill. Non-nil presents
    /// the picker; `Identifiable` lets it drive `.sheet(item:)` directly.
    @State private var contactPickerField: Field?
    @FocusState private var focus: Field?

    private enum Field: Hashable, Identifiable { case to, cc, bcc, subject, body
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider().overlay(Brand.bgDarker)

                if showChannelToggle {
                    channelToggle
                    Divider().overlay(Brand.bgDarker)
                }

                fieldsSection

                if let chatDropNotice {
                    Text(chatDropNotice)
                        .font(.footnote)
                        .foregroundStyle(Brand.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                if let offOrgWarning {
                    Text(offOrgWarning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $bodyText)
                    .composerBodyStyle()
                    .focused($focus, equals: .body)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .disabled(isSending)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { focus = mode.isReply ? .body : .to }
        .background {
            // Presented via UIKit (not a nested .sheet) so the picker's own
            // self-dismiss can't cascade and close the composer. A non-nil
            // field builds a fresh presenter; clearing it removes the host.
            if let field = contactPickerField {
                ContactPicker(
                    onPick: { email in
                        appendRecipient(email, to: field)
                        contactPickerField = nil
                    },
                    onCancel: { contactPickerField = nil }
                )
            }
        }
    }

    /// Append a picked address to the given field, comma-joining if the
    /// field already holds text so typed and picked recipients coexist.
    private func appendRecipient(_ email: String, to field: Field) {
        let add: (String) -> String = { existing in
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return email }
            let joiner = (trimmed.hasSuffix(",") || trimmed.hasSuffix(";")) ? " " : ", "
            return trimmed + joiner + email
        }
        switch field {
        case .to: toText = add(toText)
        case .cc: ccText = add(ccText)
        case .bcc: bccText = add(bccText)
        case .subject, .body: break
        }
    }

    // MARK: Type-ahead

    private func text(for field: Field) -> String {
        switch field {
        case .to: return toText
        case .cc: return ccText
        case .bcc: return bccText
        case .subject, .body: return ""
        }
    }

    private func setText(_ value: String, for field: Field) {
        switch field {
        case .to: toText = value
        case .cc: ccText = value
        case .bcc: bccText = value
        case .subject, .body: break
        }
    }

    /// Suggestions for the focused recipient field: matches against the
    /// in-progress token, minus anyone already added to that field. Empty
    /// unless the field is focused and a token is being typed.
    private func suggestions(for field: Field) -> [AddressBookEntry] {
        guard focus == field else { return [] }
        let current = text(for: field)
        guard !RecipientSuggest.activeToken(in: current).isEmpty else { return [] }
        let chosen = Set(EmailAddressValidation.parseList(current).valid.map { $0.lowercased() })
        return RecipientSuggest
            .matches(for: RecipientSuggest.activeToken(in: current), in: inbox.recipientSuggestions())
            .filter { !chosen.contains($0.address.lowercased()) }
    }

    /// Swap the in-progress token for the tapped address, keeping focus so the
    /// user can carry on to the next recipient.
    private func completeToken(with address: String, in field: Field) {
        setText(RecipientSuggest.completing(text(for: field), with: address), for: field)
        focus = field
    }

    @ViewBuilder
    private func suggestionList(for field: Field) -> some View {
        let entries = suggestions(for: field)
        if !entries.isEmpty {
            VStack(spacing: 0) {
                ForEach(entries, id: \.address) { entry in
                    Button {
                        completeToken(with: entry.address, in: field)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            if entry.name != entry.address {
                                Text(entry.address)
                                    .font(.caption)
                                    .foregroundStyle(Brand.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Brand.bgDarker.opacity(0.4))
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack {
                leadingButton
                Spacer()
                if isSending {
                    ProgressView().tint(Brand.accent)
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(canSend ? Brand.accent : Brand.bgDarker)
                            .foregroundStyle(canSend ? .white : Brand.textMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
        }
    }

    /// Cancel for a standalone sheet; Back (returning to the preview) for an
    /// inline reply. Both call `onClose` — only the affordance differs.
    @ViewBuilder
    private var leadingButton: some View {
        if presentation == .inline {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        } else {
            Button("Cancel", action: onClose)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.accent)
                .disabled(isSending)
        }
    }

    private var title: String {
        if mode.isForward { return "Forward" }
        if mode.isReply { return "Reply" }
        return channel == .chat ? "New Chat" : "New Message"
    }

    // MARK: Channel

    /// The Email/Chat segmented switch, shown only for a new message (forward
    /// is email-only). Flipping it animates the email-only fields in and out;
    /// their typed contents survive in `@State`, so a round-trip loses nothing.
    private var channelToggle: some View {
        Picker("Channel", selection: $channel.animation(.easeInOut(duration: 0.2))) {
            Text("Chat").tag(Channel.chat)
            Text("Email").tag(Channel.email)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .disabled(isSending)
    }

    /// The channel switch shows for a new message and for an email reply (which
    /// can cross to chat). Not for forward (email-only) or a chat reply (there's
    /// no address to email a chat sender back on — deferred with the lookup scope).
    private var showChannelToggle: Bool {
        switch mode {
        case .newMessage: return true
        case .forward: return false
        case .reply(let reply): return reply.source == .email
        }
    }

    /// The fields between the channel toggle and the body, one layout per mode:
    /// reply shows a "Replying to …" context line, forward a "Forwarding: …"
    /// line plus a To-only row, a new message the full To (+ Cc/Bcc/Subject
    /// in email mode) stack.
    @ViewBuilder
    private var fieldsSection: some View {
        switch mode {
        case .reply(let reply):
            replyContextLine(reply)
            Divider().overlay(Brand.bgDarker)
        case .forward(_, let subject):
            forwardingLine(subject: subject)
            Divider().overlay(Brand.bgDarker)
            recipientRow(label: "To", text: $toText, field: .to, showsDisclosure: false)
            suggestionList(for: .to)
            Divider().overlay(Brand.bgDarker)
        case .newMessage:
            recipientRow(label: "To", text: $toText, field: .to, showsDisclosure: emailFieldsShown)
            suggestionList(for: .to)
            if emailFieldsShown {
                if ccBccVisible {
                    fieldDivider
                    recipientRow(label: "Cc", text: $ccText, field: .cc)
                    suggestionList(for: .cc)
                    fieldDivider
                    recipientRow(label: "Bcc", text: $bccText, field: .bcc)
                    suggestionList(for: .bcc)
                }
                fieldDivider
                subjectRow
            }
            Divider().overlay(Brand.bgDarker)
        }
    }

    /// The "Replying to …" line, reworded by the chosen channel: same-channel
    /// keeps the thread; crossing to chat starts a fresh message to the sender.
    private func replyContextLine(_ reply: Mode.Reply) -> some View {
        Text(replyContextText(reply))
            .font(.caption)
            .foregroundStyle(Brand.textMuted)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    private func replyContextText(_ reply: Mode.Reply) -> String {
        if channel != reply.source {
            // Cross-channel — only email→chat exists today.
            return "New Teams chat with \(reply.senderName)"
        }
        switch reply.source {
        case .email: return "Replying to \(reply.senderName)\(reply.emailReplyAllTail)"
        case .chat: return "Replying in chat with \(reply.senderName)\(reply.chatOthersTail)"
        }
    }

    /// Subject / Cc / Bcc exist only for a new email — hidden in chat mode and
    /// in forward mode (To-only). Also gates the "To" disclosure chevron, since
    /// there's nothing to disclose without Cc/Bcc.
    private var emailFieldsShown: Bool {
        if case .newMessage = mode { return channel == .email }
        return false
    }

    /// In new-message chat mode, anything typed into the email-only fields won't
    /// go out — say so plainly rather than dropping it silently. The fields keep
    /// their values (restored on a flip back); this only names what a
    /// Send-as-chat would leave behind.
    private var chatDropNotice: String? {
        guard case .newMessage = mode, channel == .chat else { return nil }
        var dropped: [String] = []
        if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dropped.append("Subject") }
        if !ccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dropped.append("Cc") }
        if !bccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dropped.append("Bcc") }
        guard !dropped.isEmpty else { return nil }
        return "\(listPhrase(dropped)) won't be sent in a Teams chat."
    }

    /// The addresses a Teams chat likely can't reach — recipients (new message)
    /// or the email sender (cross-channel reply) whose domain isn't the org's.
    /// A warning, not a block: an in-tenant guest carries an outside domain but
    /// is still chattable, so we flag and let the send proceed with Graph as the
    /// final word. Empty before `/me` loads (no org domain to judge against).
    private var offOrgAddresses: [String] {
        let org = inbox.currentUserDomain
        switch mode {
        case .newMessage where channel == .chat:
            return EmailAddressValidation.offDomainRecipients(in: toText, orgDomain: org)
        case .reply(let reply) where channel == .chat && reply.source == .email:
            return EmailAddressValidation.offDomainRecipients(in: reply.senderAddress ?? "", orgDomain: org)
        default:
            return []
        }
    }

    private var offOrgWarning: String? {
        let who = offOrgAddresses
        guard !who.isEmpty else { return nil }
        let verb = who.count == 1 ? "isn't" : "aren't"
        return "\(listPhrase(who)) \(verb) in your organization and may not be reachable on Teams."
    }

    /// "Subject" / "Subject and Cc" / "Subject, Cc, and Bcc".
    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    // MARK: Fields

    private func recipientRow(label: String, text: Binding<String>,
                              field: Field, showsDisclosure: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showsDisclosure {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showCcBcc.toggle() }
                } label: {
                    HStack(spacing: 2) {
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(Brand.textMuted)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Brand.textMuted)
                            .rotationEffect(.degrees(ccBccVisible ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isSending)
                .accessibilityLabel(ccBccVisible ? "Hide Cc and Bcc" : "Show Cc and Bcc")
            } else {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Brand.textMuted)
                    .fixedSize()
            }
            TextField("", text: text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(Brand.accent)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .disabled(isSending)
            Button {
                contactPickerField = field
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(label) from Contacts")
            .disabled(isSending)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Cc and Bcc appear once the "To" label is tapped to disclose them, or
    /// once either already holds text — so collapsing can never hide a
    /// recipient that's been entered.
    private var ccBccVisible: Bool {
        showCcBcc
            || !ccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var subjectRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Subject")
                .font(.subheadline)
                .foregroundStyle(Brand.textMuted)
                .fixedSize()
            TextField("", text: $subject)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(Brand.accent)
                .focused($focus, equals: .subject)
                .disabled(isSending)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var fieldDivider: some View {
        Divider().overlay(Brand.bgDarker).padding(.leading, 20)
    }

    /// The "Forwarding: <subject>" context line shown above the recipient
    /// field in forward mode, so it's clear which message is going out.
    private func forwardingLine(subject: String) -> some View {
        Text("Forwarding: \(subject.isEmpty ? "(no subject)" : subject)")
            .font(.caption)
            .foregroundStyle(Brand.textMuted)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    // MARK: Send

    /// Reply needs a non-empty body (the recipient is the thread); compose and
    /// forward need a recipient (address validation runs in `send()` so the
    /// button doesn't re-parse on every keystroke).
    private var canSend: Bool {
        guard !isSending else { return false }
        if mode.isReply {
            return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        if case .reply(let reply) = mode {
            await sendReply(reply)
            return
        }
        // Cc/Bcc are parsed only for an email; forward and chat are To-only.
        let to = EmailAddressValidation.parseList(toText)
        let cc = emailFieldsShown ? EmailAddressValidation.parseList(ccText) : (valid: [], invalid: [])
        let bcc = emailFieldsShown ? EmailAddressValidation.parseList(bccText) : (valid: [], invalid: [])

        let invalid = to.invalid + cc.invalid + bcc.invalid
        guard invalid.isEmpty else {
            errorMessage = "Not a valid address: \(invalid.joined(separator: ", "))"
            return
        }
        guard !to.valid.isEmpty else {
            errorMessage = "Add at least one recipient."
            return
        }
        // A chat's first message is that message — an empty one is degenerate
        // and Graph rejects it. Email tolerates an empty body, so only guard chat.
        if channel == .chat, !mode.isForward,
           bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Add a message to send."
            return
        }

        isSending = true
        errorMessage = nil
        do {
            switch mode {
            case .reply:
                return  // handled by sendReply via the early return above
            case .newMessage where channel == .chat:
                #if DEBUG
                log.info("compose chat: to=\(to.valid.count)")
                #endif
                try await inbox.startChat(withEmails: to.valid, message: bodyText)
            case .newMessage:
                #if DEBUG
                log.info("compose send: to=\(to.valid.count) cc=\(cc.valid.count) bcc=\(bcc.valid.count)")
                #endif
                try await inbox.sendNewEmail(
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: bodyText,
                    to: to.valid, cc: cc.valid, bcc: bcc.valid
                )
            case .forward(let emailId, _):
                #if DEBUG
                log.info("compose forward: id=\(emailId, privacy: .public) to=\(to.valid.count)")
                #endif
                try await inbox.forwardEmail(
                    emailId: emailId,
                    comment: bodyText,
                    to: to.valid
                )
            }
            isSending = false
            (onSent ?? onClose)()
        } catch {
            isSending = false
            #if DEBUG
            log.error("compose send failed: \(error.localizedDescription, privacy: .public)")
            #endif
            errorMessage = sendFailureMessage(error)
        }
    }

    /// Send a reply. Same-channel keeps thread semantics (email `replyAll`,
    /// chat post-into-thread); crossing email→chat starts a fresh chat with the
    /// sender, the body prefixed with a one-line "Re: <subject>" reference.
    private func sendReply(_ reply: Mode.Reply) async {
        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Add a message to send."
            return
        }
        isSending = true
        errorMessage = nil
        do {
            if channel == reply.source {
                switch reply.source {
                case .email:
                    guard let id = reply.emailId else { throw GraphError.invalidResponse }
                    #if DEBUG
                    log.info("reply email: id=\(id, privacy: .public)")
                    #endif
                    try await inbox.replyAllToEmail(emailId: id, comment: bodyText)
                case .chat:
                    guard let id = reply.chatId else { throw GraphError.invalidResponse }
                    #if DEBUG
                    log.info("reply chat: id=\(id, privacy: .public)")
                    #endif
                    try await inbox.sendChatMessage(chatId: id, content: bodyText)
                }
            } else {
                // Cross-channel: email→chat only. Prefix the sender's message
                // with a one-line reference so the chat carries the email's context.
                guard let address = reply.senderAddress, !address.isEmpty else {
                    throw GraphError.invalidResponse
                }
                #if DEBUG
                log.info("reply cross email->chat: to=1")
                #endif
                let message = "Re: \(reply.reference)\n\n\(bodyText)"
                try await inbox.startChat(withEmails: [address], message: message)
            }
            isSending = false
            (onSent ?? onClose)()
        } catch {
            isSending = false
            #if DEBUG
            log.error("reply failed: \(error.localizedDescription, privacy: .public)")
            #endif
            errorMessage = sendFailureMessage(error)
        }
    }

    /// A chat to an out-of-org address is the likely-culprit failure, so name
    /// it rather than dump the raw Graph error.
    private func sendFailureMessage(_ error: Error) -> String {
        if channel == .chat, !offOrgAddresses.isEmpty {
            return "Couldn't start the chat — \(listPhrase(offOrgAddresses)) may not be on Teams in your organization."
        }
        return "Couldn't send: \(error.localizedDescription)"
    }
}
