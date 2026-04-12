import CoreLocation
import Foundation
import MapKit

public protocol WalkingETAProviding: Sendable {
    func walkingMinutes(from location: CLLocationCoordinate2D, to stop: Stop) async -> Int?
}

public struct WalkingETAService: WalkingETAProviding {
    public init() {}

    public func walkingMinutes(from location: CLLocationCoordinate2D, to stop: Stop) async -> Int? {
        guard let lat = stop.latitude, let lon = stop.longitude else {
            return nil
        }
        let destination = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        let request = MKDirections.Request()
        request.source = mapItem(for: location)
        request.destination = mapItem(for: destination)
        request.transportType = .walking

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculateETA()
            return max(1, Int((response.expectedTravelTime / 60).rounded(.up)))
        } catch {
            return nil
        }
    }

    private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        #if SWIFT_PACKAGE
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            return modernMapItem(for: location)
        }

        return legacyMapItem(for: coordinate)
        #else
        return modernMapItem(for: location)
        #endif
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    private func modernMapItem(for location: CLLocation) -> MKMapItem {
        MKMapItem(location: location, address: nil)
    }

    @available(iOS, introduced: 6.0, deprecated: 26.0)
    @available(macOS, introduced: 10.9, deprecated: 26.0)
    @available(tvOS, introduced: 9.2, deprecated: 26.0)
    @available(watchOS, introduced: 2.0, deprecated: 26.0)
    private func legacyMapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }
}
