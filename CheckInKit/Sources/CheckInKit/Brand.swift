// Brand.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

public enum Brand {
    public static let bg        = Color(hex: 0x0D2D5B)
    public static let bgDarker  = Color(hex: 0x06142A)
    public static let accent    = Color(hex: 0x00ADEE)
    public static let accentDim = Color(hex: 0x0072A4)
    public static let textMuted = Color(hex: 0x6a8899)
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
