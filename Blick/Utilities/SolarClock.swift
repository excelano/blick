// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Bogenzeit
import BlickKit
import Foundation

struct SolarClock {
    let latitude: Double
    let longitude: Double
    let scale: Scale
    let precision: Precision
    let hidesCivilTime: Bool

    init?(enabled: Bool, latitude: Double?, longitude: Double?, scale: String, precision: Int, hidesCivilTime: Bool) {
        guard enabled, let latitude, let longitude else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.scale = Scale(rawValue: scale) ?? .standard
        self.precision = Precision(rawValue: precision) ?? .standard
        self.hidesCivilTime = hidesCivilTime
    }

    static var current: SolarClock? {
        let defaults = UserDefaults.standard
        return SolarClock(
            enabled: defaults.bool(forKey: AppStorageKey.bogenzeit),
            latitude: defaults.object(forKey: AppStorageKey.bogenzeitLatitude) as? Double,
            longitude: defaults.object(forKey: AppStorageKey.bogenzeitLongitude) as? Double,
            scale: defaults.string(forKey: AppStorageKey.bogenzeitScale) ?? Scale.standard.rawValue,
            precision: defaults.object(forKey: AppStorageKey.bogenzeitPrecision) as? Int ?? Precision.standard.rawValue,
            hidesCivilTime: defaults.bool(forKey: AppStorageKey.bogenzeitHidesCivilTime)
        )
    }

    func position(at instant: Date) -> DisplayedPosition {
        DisplayedPosition(Reading(at: instant, latitude: latitude, longitude: longitude), scale: scale, precision: precision)
    }

    func spoken(_ position: DisplayedPosition) -> String {
        guard let number = position.number else { return position.glyph.name }
        let unit = position.unit == nil ? "spans" : "kiloseconds"
        let side = position.side == .before ? "before" : "after"
        return "\(number) \(unit) \(side) \(position.glyph.name)"
    }

    func spokenRange(start: Date, end: Date) -> String {
        "\(spoken(position(at: start))) to \(spoken(position(at: end)))"
    }

    func countdown(to start: Date, from now: Date) -> String {
        "in \(duration(from: start, to: now).text(scale))"
    }

    func elapsed(since date: Date, now: Date) -> String {
        let duration = duration(from: date, to: now)
        let steps = scale == .spans ? duration.displaySpans ?? duration.displayKsSteps : duration.displayKsSteps
        return steps < 1 ? "just now" : "\(duration.text(scale)) ago"
    }

    private func duration(from: Date, to: Date) -> SolarDuration {
        SolarDuration(from: from, to: to, latitude: latitude, longitude: longitude)
    }
}

func meetingCountdown(_ start: Date, referenceDate: Date) -> String {
    guard !isMeetingImminent(start, referenceDate: referenceDate),
          start > referenceDate,
          let clock = SolarClock.current
    else { return untilTime(start, referenceDate: referenceDate) }
    return clock.countdown(to: start, from: referenceDate)
}

func spokenCountdown(_ start: Date, referenceDate: Date) -> String {
    meetingCountdown(start, referenceDate: referenceDate).replacingOccurrences(of: " ks", with: " kiloseconds")
}

func meetingTimeSpeech(start: Date, end: Date) -> String {
    let civil = meetingTimeRange(start: start, end: end)
    guard let clock = SolarClock.current else { return civil }
    let solar = clock.spokenRange(start: start, end: end)
    return clock.hidesCivilTime ? solar : "\(solar), \(civil)"
}
