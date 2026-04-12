import CoreLocation
import Foundation

public protocol LocationProviding: Sendable {
    func requestAuthorization() async
    func currentLocation() async -> CLLocationCoordinate2D?
    func authorizationStatus() -> CLAuthorizationStatus
}

public final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private let lock = NSLock()

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func requestAuthorization() async {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            authContinuation = continuation
            lock.unlock()
            #if os(macOS)
            manager.requestAlwaysAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
        }
    }

    public func authorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    public func currentLocation() async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        guard isAuthorized(status) else {
            return nil
        }

        // If we have a recent cached location (< 60s old), use it
        if let cached = manager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 60 {
            return cached.coordinate
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            lock.lock()
            locationContinuation = continuation
            lock.unlock()
            manager.requestLocation()
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        status == .authorized || status == .authorizedAlways
        #else
        status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lock.lock()
        let continuation = locationContinuation
        locationContinuation = nil
        lock.unlock()
        continuation?.resume(returning: locations.last?.coordinate)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lock.lock()
        let continuation = locationContinuation
        locationContinuation = nil
        lock.unlock()
        continuation?.resume(returning: nil)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        lock.lock()
        let continuation = authContinuation
        authContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
