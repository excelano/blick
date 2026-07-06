// ComposeView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI
#if DEBUG
import os
private let log = Logger(subsystem: "com.excelano.checkin", category: "compose")
#endif

/// Full-sheet composer, used for two jobs: a brand-new email and forwarding an
/// existing one. Distinct from `ReplyComposerView` (which swaps in place inside
/// the preview sheet and has no recipient concept): this owns the recipient
/// fields, validated with `EmailAddressValidation`, and the Contacts picker.
///
/// New-message mode shows To / Cc / Bcc, a subject, and a plain-text body.
/// Forward mode shows only To plus an optional note — Graph's `/forward`
/// endpoint builds the "Fwd:" subject and quotes the original server-side and
/// accepts only `toRecipients`, so there's no subject field, no Cc/Bcc, and no
/// need to load the original body.
///
/// On Send the view goes to a loading state; Graph success calls `onClose`
/// (dismissing the sheet); Graph failure surfaces the error inline and leaves
/// everything typed so the user can retry without re-entering it.
struct ComposeView: View {
    var inbox: Inbox
    let onClose: () -> Void
    var mode: Mode = .newMessage

    enum Mode {
        case newMessage
        /// Forward this message. Carries only what the sheet needs to label
        /// itself and to call `/forward` — the id and the subject.
        case forward(emailId: String, subject: String)

        var isForward: Bool {
            if case .forward = self { return true }
            return false
        }
    }

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

                if case .forward(_, let subject) = mode {
                    forwardingLine(subject: subject)
                    Divider().overlay(Brand.bgDarker)
                }

                recipientRow(label: "To", text: $toText, field: .to,
                             showsDisclosure: !mode.isForward)

                if !mode.isForward {
                    if ccBccVisible {
                        fieldDivider
                        recipientRow(label: "Cc", text: $ccText, field: .cc)
                        fieldDivider
                        recipientRow(label: "Bcc", text: $bccText, field: .bcc)
                    }
                    fieldDivider
                    subjectRow
                }
                Divider().overlay(Brand.bgDarker)

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
        .onAppear { focus = .to }
        .sheet(item: $contactPickerField) { field in
            ContactPicker(
                onPick: { email in
                    appendRecipient(email, to: field)
                    contactPickerField = nil
                },
                onCancel: { contactPickerField = nil }
            )
            .ignoresSafeArea()
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

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(mode.isForward ? "Forward" : "New Message")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack {
                Button("Cancel", action: onClose)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.accent)
                    .disabled(isSending)
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

    /// Enabled once the To line has any text; full address validation runs
    /// in `send()` so the button doesn't have to re-parse on every keystroke.
    private var canSend: Bool {
        !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send() async {
        // Forward mode only collects To; new-message mode also parses Cc/Bcc.
        let to = EmailAddressValidation.parseList(toText)
        let cc = mode.isForward ? (valid: [], invalid: []) : EmailAddressValidation.parseList(ccText)
        let bcc = mode.isForward ? (valid: [], invalid: []) : EmailAddressValidation.parseList(bccText)

        let invalid = to.invalid + cc.invalid + bcc.invalid
        guard invalid.isEmpty else {
            errorMessage = "Not a valid address: \(invalid.joined(separator: ", "))"
            return
        }
        guard !to.valid.isEmpty else {
            errorMessage = "Add at least one recipient."
            return
        }

        isSending = true
        errorMessage = nil
        do {
            switch mode {
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
            onClose()
        } catch {
            isSending = false
            #if DEBUG
            log.error("compose send failed: \(error.localizedDescription, privacy: .public)")
            #endif
            errorMessage = "Couldn't send: \(error.localizedDescription)"
        }
    }
}
