// ContactPicker.swift
// Blick
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import ContactsUI
import SwiftUI

/// SwiftUI bridge to `CNContactPickerViewController`. The picker runs out of
/// process in Contacts' own UI, so it needs NO Contacts permission, NO
/// `NSContactsUsageDescription`, and NO `People.Read` scope — it hands back
/// only the one address the user taps, nothing else from the address book
/// ever reaches us.
///
/// It is deliberately NOT presented as a SwiftUI `.sheet`. The picker
/// dismisses *itself* after a selection, and when it's the content of a sheet
/// stacked on the composer's own sheet, that self-dismiss cascades and tears
/// the composer down too. So this hosts an empty controller and presents the
/// picker modally on it from UIKit: the self-dismiss then only closes the
/// picker, and the composer stays put. Drop this into a `.background` gated on
/// a non-nil "which field" state; clearing that state removes the host.
///
/// Contacts with no email are disabled. A single-email contact selects
/// immediately (`didSelect contact:`); a multi-email contact drills into its
/// detail so the user taps a specific address (`didSelect property:`). Either
/// way `onPick` receives one address with the contact's name; cancel calls
/// `onCancel`.
/// One selection from the picker: the address the user tapped and the
/// contact's name, which is empty when Contacts did not supply one.
struct PickedContact {
    let displayName: String
    let address: String
}

struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (PickedContact) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.presentIfNeeded(from: host)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (PickedContact) -> Void
        private let onCancel: () -> Void
        private var didPresent = false

        init(onPick: @escaping (PickedContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        /// Present the picker once, on the next runloop so the host has
        /// joined the window hierarchy. A fresh `ContactPicker` (and thus a
        /// fresh coordinator with `didPresent == false`) is created each time
        /// the field state flips non-nil, so this fires exactly once per open.
        func presentIfNeeded(from host: UIViewController) {
            guard !didPresent else { return }
            didPresent = true
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
            picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
            picker.predicateForSelectionOfContact = NSPredicate(format: "emailAddresses.@count == 1")
            DispatchQueue.main.async {
                host.present(picker, animated: true)
            }
        }

        /// Single-email contact: take its one address.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let email = contact.emailAddresses.first?.value as String? else {
                onCancel()
                return
            }
            onPick(PickedContact(displayName: Self.fullName(of: contact), address: email))
        }

        /// Multi-email contact: the user tapped a specific email on the card.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let email = contactProperty.value as? String else {
                onCancel()
                return
            }
            onPick(PickedContact(displayName: Self.fullName(of: contactProperty.contact), address: email))
        }

        /// The contact's formatted name, or empty when the picker handed back
        /// a contact without the name keys. Callers fall back to the address.
        private static func fullName(of contact: CNContact) -> String {
            let required = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            guard contact.areKeysAvailable([required]) else { return "" }
            return CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
