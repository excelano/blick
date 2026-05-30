// CheckInWatchWidgetBundle.swift
// CheckInWatchWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import WidgetKit

@main
struct CheckInWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheckInWatchCornerWidget()
        CheckInWatchRectangularWidget()
        CheckInWatchCircularWidget()
        CheckInWatchInlineWidget()
    }
}
