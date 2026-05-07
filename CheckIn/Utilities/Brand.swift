// Brand.swift
// CheckIn
// Excelano brand colors
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

enum Brand {
    static let bg        = Color(hex: 0x0f2233)
    static let bgDarker  = Color(hex: 0x080f17)
    static let accent    = Color(hex: 0x2ab8d0)
    static let accentDim = Color(hex: 0x0d7a8f)
    static let textMuted = Color(hex: 0x6a8899)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
