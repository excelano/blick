// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Bogenzeit
import BogenzeitUI
import SwiftUI

public extension EnvironmentValues {
    @Entry var solarClock: SolarClock?
}

public struct MeetingTimeLabel: View {
    let start: Date
    let end: Date
    let style: Font.TextStyle
    let weight: Font.Weight
    let color: Color
    let civilStyle: Font.TextStyle
    let includePeriod: Bool
    let stacksCivil: Bool

    @Environment(\.solarClock) private var clock

    public init(
        start: Date,
        end: Date,
        style: Font.TextStyle = .subheadline,
        weight: Font.Weight = .semibold,
        color: Color,
        civilStyle: Font.TextStyle = .caption,
        includePeriod: Bool = true,
        stacksCivil: Bool = true
    ) {
        self.start = start
        self.end = end
        self.style = style
        self.weight = weight
        self.color = color
        self.civilStyle = civilStyle
        self.includePeriod = includePeriod
        self.stacksCivil = stacksCivil
    }

    public var body: some View {
        if let clock {
            let solar = SolarRange(clock: clock, start: start, end: end, style: style, weight: weight, color: color)
            if clock.hidesCivilTime || !stacksCivil {
                solar
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    solar
                    civil(style: civilStyle, weight: .regular, color: Brand.textMuted)
                }
            }
        } else {
            civil(style: style, weight: weight, color: color)
        }
    }

    private func civil(style: Font.TextStyle, weight: Font.Weight, color: Color) -> some View {
        Text(meetingTimeRange(start: start, end: end, includePeriod: includePeriod))
            .font(.system(style, weight: weight).monospacedDigit())
            .foregroundStyle(color)
    }
}

public struct MessageTimeLabel: View {
    let date: Date

    @Environment(\.solarClock) private var clock

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        if let clock {
            let solar = SolarPosition(position: clock.position(at: date), style: .caption2, weight: .regular, color: .secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clock.spoken(clock.position(at: date)))
            if clock.hidesCivilTime {
                solar
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    solar
                    civil
                }
            }
        } else {
            civil
        }
    }

    private var civil: some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
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
