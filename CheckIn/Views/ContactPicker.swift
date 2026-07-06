// ContactPicker.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import ContactsUI
import SwiftUI

/// SwiftUI wrapper over `CNContactPickerViewController`. The picker runs
/// out of process in Contacts' own UI, so it needs NO Contacts permission,
/// NO `NSContactsUsageDescription`, and NO `People.Read` scope — it hands
/// back only the one address the user taps, nothing else from the address
/// book ever reaches us.
///
/// Contacts with no email are disabled. A single-email contact selects
/// immediately (`didSelect contact:`); a multi-email contact drills into its
/// detail so the user taps a specific address (`didSelect property:`). Either
/// way `onPick` receives one SMTP address string; cancel calls `onCancel`.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Show and allow selection of the email field only.
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        // Grey out contacts with no email at all.
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        // A contact with exactly one email returns immediately; one with
        // several opens its card so the user picks which address.
        picker.predicateForSelectionOfContact = NSPredicate(format: "emailAddresses.@count == 1")
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (String) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        /// Single-email contact: take its one address.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let email = contact.emailAddresses.first?.value as String? else {
                onCancel()
                return
            }
            onPick(email)
        }

        /// Multi-email contact: the user tapped a specific email on the card.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let email = contactProperty.value as? String else {
                onCancel()
                return
            }
            onPick(email)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
