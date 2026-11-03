// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Bogenzeit
import BogenzeitUI
import BlickKit
import SwiftUI

struct MeetingTimeLabel: View {
    let start: Date
    let end: Date
    let color: Color

    @AppStorage(AppStorageKey.bogenzeit) private var enabled = false
    @AppStorage(AppStorageKey.bogenzeitLatitude) private var latitude: Double?
    @AppStorage(AppStorageKey.bogenzeitLongitude) private var longitude: Double?
    @AppStorage(AppStorageKey.bogenzeitScale) private var scale = Scale.standard.rawValue
    @AppStorage(AppStorageKey.bogenzeitPrecision) private var precision = Precision.standard.rawValue
    @AppStorage(AppStorageKey.bogenzeitHidesCivilTime) private var hidesCivilTime = false

    private var clock: SolarClock? {
        SolarClock(enabled: enabled, latitude: latitude, longitude: longitude,
                   scale: scale, precision: precision, hidesCivilTime: hidesCivilTime)
    }

    var body: some View {
        if let clock {
            let solar = SolarRange(clock: clock, start: start, end: end, style: .subheadline, weight: .semibold, color: color)
            if clock.hidesCivilTime {
                solar
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    solar
                    civil(font: .caption, color: Brand.textMuted)
                }
            }
        } else {
            civil(font: .subheadline.weight(.semibold), color: color)
        }
    }

    private func civil(font: Font, color: Color) -> some View {
        Text(meetingTimeRange(start: start, end: end))
            .font(font)
            .foregroundStyle(color)
    }
}

private struct SolarRange: View {
    let clock: SolarClock
    let start: Date
    let end: Date
    let style: Font.TextStyle
    let weight: Font.Weight
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            SolarPosition(position: clock.position(at: start), style: style, weight: weight, color: color)
            Text("–")
                .font(.system(style, weight: weight))
                .foregroundStyle(color)
            SolarPosition(position: clock.position(at: end), style: style, weight: weight, color: color)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clock.spokenRange(start: start, end: end))
    }
}

private struct SolarPosition: View {
    let position: DisplayedPosition
    let font: Font
    let color: Color
    @ScaledMetric private var radius: CGFloat

    init(position: DisplayedPosition, style: Font.TextStyle, weight: Font.Weight, color: Color) {
        self.position = position
        self.font = .system(style, weight: weight).monospacedDigit()
        self.color = color
        _radius = ScaledMetric(wrappedValue: Self.baseRadius(style), relativeTo: style)
    }

    var body: some View {
        HStack(spacing: radius * 0.5) {
            if position.side == .before, let value { value }
            GlyphView(position.glyph, radius: radius, lineWidth: radius * 0.24, color: color)
            if position.side == .after, let value { value }
        }
    }

    private var value: Text? {
        guard let number = position.number else { return nil }
        let text = position.unit.map { "\(number) \($0)" } ?? number
        return Text(text).font(font).foregroundStyle(color)
    }

    private static func baseRadius(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .caption, .caption2, .footnote: 4.5
        default: 6
        }
    }
}
