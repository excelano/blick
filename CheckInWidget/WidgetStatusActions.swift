// WidgetStatusActions.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInGraph
import CheckInKit
import Foundation
import WidgetKit

/// Backs the `StatusActions` the widget extension registers for its
/// interactive presence / Out-of-Office controls. Each action builds a
/// `GraphCore` over `WidgetTokenProvider` (so all of its Graph work shares one
/// token acquire), issues the mutation, then patches the App Group snapshot so
/// the widget reflects the change. On failure the prior snapshot is left
/// untouched and a reload lets the toggle settle back to it.
struct WidgetStatusActions: Sendable {
    private let defaultOutOfOfficeMessage =
        "I'm currently out of the office and will respond when I return."

    /// Set the user's preferred presence (or clear to auto for `.unknown`),
    /// keeping CheckIn's presence session alive so Graph honors the override.
    /// Mirrors `Inbox.setPresence`, including turning Out of Office off when a
    /// presence is explicitly chosen.
    func applyPresence(_ presence: Presence) async throws {
        let wasOutOfOffice = currentSnapshot()?.isOutOfOffice == true
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        do {
            // Best-effort session heartbeat (Available); failure here
            // shouldn't block the preferred-presence set.
            try? await core.setSessionPresence(
                sessionId: widgetEffectiveConfig().clientID, presence: .available
            )

            if presence == .unknown {
                try await core.clearUserPreferredPresence()
            } else {
                try await core.setUserPreferredPresence(presence)
            }

            // Choosing a presence also clears Out of Office, matching the picker.
            if wasOutOfOffice {
                try? await core.disableAutomaticReplies()
            }
            patchSnapshot(presence: presence, isOutOfOffice: false)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }

    /// Turn Outlook automatic replies on or off. Snapshot written once on
    /// success, left untouched on failure.
    func applyOutOfOffice(_ on: Bool) async throws {
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        do {
            if on {
                try await core.enableAutomaticReplies(defaultMessage: defaultOutOfOfficeMessage)
            } else {
                try await core.disableAutomaticReplies()
            }
            let presence = currentSnapshot()?.presence ?? .unknown
            patchSnapshot(presence: presence, isOutOfOffice: on)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }

    private func currentSnapshot() -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier),
              let data = defaults.data(forKey: CheckInSnapshot.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
    }

    private func patchSnapshot(presence: Presence, isOutOfOffice: Bool) {
        guard let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier),
              let existing = currentSnapshot(),
              let data = try? JSONEncoder().encode(
                  existing.settingStatus(presence: presence, isOutOfOffice: isOutOfOffice)
              ) else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        defaults.set(data, forKey: CheckInSnapshot.userDefaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
