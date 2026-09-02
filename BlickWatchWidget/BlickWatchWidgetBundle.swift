// BlickWatchWidgetBundle.swift
// BlickWatchWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import WidgetKit

@main
struct BlickWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlickWatchCornerWidget()
        BlickWatchRectangularWidget()
        BlickWatchCircularWidget()
        BlickWatchInlineWidget()
    }
}
