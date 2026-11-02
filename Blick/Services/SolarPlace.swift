// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CoreLocation
import Foundation

final class SolarPlace: NSObject, CLLocationManagerDelegate {
    static let shared = SolarPlace()

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Bool, Never>] = []
    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func enable() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
            if granted { manager.requestLocation() }
            return granted
        default:
            return false
        }
    }

    func disable() {
        defaults.set(false, forKey: AppStorageKey.bogenzeit)
        defaults.removeObject(forKey: AppStorageKey.bogenzeitLatitude)
        defaults.removeObject(forKey: AppStorageKey.bogenzeitLongitude)
    }

    func refresh() {
        guard defaults.bool(forKey: AppStorageKey.bogenzeit) else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            disable()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard status != .notDetermined else { return }
            let granted = status == .authorizedWhenInUse || status == .authorizedAlways
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: granted) }
            if !granted && waiters.isEmpty && defaults.bool(forKey: AppStorageKey.bogenzeit) {
                disable()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        MainActor.assumeIsolated {
            guard defaults.bool(forKey: AppStorageKey.bogenzeit) else { return }
            defaults.set(coordinate.latitude, forKey: AppStorageKey.bogenzeitLatitude)
            defaults.set(coordinate.longitude, forKey: AppStorageKey.bogenzeitLongitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
