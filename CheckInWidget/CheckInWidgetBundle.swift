// CheckInWidgetBundle.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import WidgetKit
import SwiftUI
import AppIntents
import CheckInKit

@main
struct CheckInWidgetBundle: WidgetBundle {
    init() {
        // On iOS 18+ an interactive-widget intent runs in THIS extension
        // process, not the app, so the intents' `@Dependency var actions`
        // must resolve here too. Wire it to the extension's own Graph client.
        // The app registers its own StatusActions (→ Inbox) for Siri/Shortcuts.
        AppDependencyManager.shared.add(
            dependency: StatusActions(
                presence: { try await WidgetStatusActions().applyPresence($0) },
                outOfOffice: { try await WidgetStatusActions().applyOutOfOffice($0) }
            )
        )
    }

    var body: some Widget {
        CheckInWidget()
        if #available(iOS 18.0, *) {
            OutOfOfficeControl()
            SetAvailableControl()
            SetBusyControl()
            SetDoNotDisturbControl()
            SetBeRightBackControl()
            SetAwayControl()
            SetOfflineControl()
            ResetStatusControl()
        }
    }
}
