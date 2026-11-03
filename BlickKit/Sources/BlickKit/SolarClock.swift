// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Bogenzeit
import Foundation

public struct SolarClock: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let scale: Scale
    public let precision: Precision
    public let hidesCivilTime: Bool

    public init?(enabled: Bool, latitude: Double?, longitude: Double?, scale: String, precision: Int, hidesCivilTime: Bool) {
        guard enabled, let latitude, let longitude else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.scale = Scale(rawValue: scale) ?? .standard
        self.precision = Precision(rawValue: precision) ?? .standard
        self.hidesCivilTime = hidesCivilTime
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, scale, precision, hidesCivilTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        scale = Scale(rawValue: try c.decode(String.self, forKey: .scale)) ?? .standard
        precision = Precision(rawValue: try c.decode(Int.self, forKey: .precision)) ?? .standard
        hidesCivilTime = try c.decode(Bool.self, forKey: .hidesCivilTime)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(scale.rawValue, forKey: .scale)
        try c.encode(precision.rawValue, forKey: .precision)
        try c.encode(hidesCivilTime, forKey: .hidesCivilTime)
    }

    public static let userDefaultsKey = "solarClock"

    public static func load(suite: String = BlickSnapshot.appGroupIdentifier) -> SolarClock? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(SolarClock.self, from: data)
    }

    public static func save(_ clock: SolarClock?, suite: String = BlickSnapshot.appGroupIdentifier) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        if let clock, let data = try? JSONEncoder().encode(clock) {
            defaults.set(data, forKey: userDefaultsKey)
        } else {
            defaults.removeObject(forKey: userDefaultsKey)
        }
    }

    public func position(at instant: Date) -> DisplayedPosition {
        DisplayedPosition(Reading(at: instant, latitude: latitude, longitude: longitude), scale: scale, precision: precision)
    }

    public func spoken(_ position: DisplayedPosition) -> String {
        guard let number = position.number else { return position.glyph.name }
        let unit = position.unit == nil ? "spans" : "kiloseconds"
        let side = position.side == .before ? "before" : "after"
        return "\(number) \(unit) \(side) \(position.glyph.name)"
    }

    public func spokenRange(start: Date, end: Date) -> String {
        "\(spoken(position(at: start))) to \(spoken(position(at: end)))"
    }

    public func countdown(to start: Date, from now: Date) -> String {
        "in \(duration(from: start, to: now).text(scale))"
    }

    public func elapsed(since date: Date, now: Date) -> String {
        let duration = duration(from: date, to: now)
        let steps = scale == .spans ? duration.displaySpans ?? duration.displayKsSteps : duration.displayKsSteps
        return steps < 1 ? "just now" : "\(duration.text(scale)) ago"
    }

    private func duration(from: Date, to: Date) -> SolarDuration {
        SolarDuration(from: from, to: to, latitude: latitude, longitude: longitude)
    }
}

public func meetingCountdown(_ start: Date, referenceDate: Date, clock: SolarClock?) -> String {
    guard !isMeetingImminent(start, referenceDate: referenceDate),
          start > referenceDate,
          let clock
    else { return untilTime(start, referenceDate: referenceDate) }
    return clock.countdown(to: start, from: referenceDate)
}

public func spokenCountdown(_ start: Date, referenceDate: Date, clock: SolarClock?) -> String {
    meetingCountdown(start, referenceDate: referenceDate, clock: clock)
        .replacingOccurrences(of: " ks", with: " kiloseconds")
}

public func meetingTimeSpeech(start: Date, end: Date, clock: SolarClock?) -> String {
    let civil = meetingTimeRange(start: start, end: end)
    guard let clock else { return civil }
    let solar = clock.spokenRange(start: start, end: end)
    return clock.hidesCivilTime ? solar : "\(solar), \(civil)"
}
