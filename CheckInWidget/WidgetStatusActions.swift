// WidgetStatusActions.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInGraph
import CheckInKit
import Foundation
import os

private let log = Logger(subsystem: "com.excelano.checkin", category: "widget")

/// Backs the `StatusActions` the widget extension registers for its
/// interactive presence / Out-of-Office controls. Each action builds a
/// `GraphCore` over `WidgetTokenProvider` (so all of its Graph work shares one
/// token acquire), issues the mutation, then patches the App Group snapshot so
/// the widget reflects the change. On failure the prior snapshot is left
/// untouched and a reload lets the toggle settle back to it.
struct WidgetStatusActions: Sendable {
    /// Set the user's preferred presence (or clear to auto for `.unknown`),
    /// keeping CheckIn's presence session alive so Graph honors the override.
    /// Mirrors `Inbox.setPresence`, including turning Out of Office off when a
    /// presence is explicitly chosen.
    func applyPresence(_ presence: Presence) async throws {
        let wasOutOfOffice = CheckInSnapshot.loadFromAppGroup()?.isOutOfOffice == true
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        do {
            // Best-effort session heartbeat (Available); failure here
            // shouldn't block the preferred-presence set.
            do {
                try await core.setSessionPresence(
                    sessionId: widgetEffectiveConfig().clientID, presence: .available
                )
            } catch {
                log.error("session heartbeat failed: \(error.localizedDescription, privacy: .public)")
            }

            if presence == .unknown {
                try await core.clearUserPreferredPresence()
            } else {
                try await core.setUserPreferredPresence(presence)
            }

            // Choosing a presence also clears Out of Office, matching the picker.
            if wasOutOfOffice {
                do {
                    try await core.disableAutomaticReplies()
                } catch {
                    log.error("OOO disable failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            CheckInSnapshot.patchAndReload(presence: presence, isOutOfOffice: false)
        } catch {
            log.error("applyPresence failed: \(error.localizedDescription, privacy: .public)")
            CheckInSnapshot.reloadStatusSurfaces()
            throw error
        }
    }

    /// Turn Outlook automatic replies on or off. Snapshot written once on
    /// success, left untouched on failure.
    func applyOutOfOffice(_ on: Bool) async throws {
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        do {
            if on {
                try await core.enableAutomaticReplies(
                    defaultMessage: CheckInSnapshot.defaultOutOfOfficeMessage
                )
            } else {
                try await core.disableAutomaticReplies()
            }
            let presence = CheckInSnapshot.loadFromAppGroup()?.presence ?? .unknown
            CheckInSnapshot.patchAndReload(presence: presence, isOutOfOffice: on)
        } catch {
            log.error("applyOutOfOffice failed: \(error.localizedDescription, privacy: .public)")
            CheckInSnapshot.reloadStatusSurfaces()
            throw error
        }
    }
}
