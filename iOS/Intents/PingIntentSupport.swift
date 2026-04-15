import Foundation
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

@MainActor
enum PingIntentDependencies {
    static let sharedContainer = SharedContainer(bundle: .main)
}

enum PingIntentSupport {
    static func container() async -> SharedContainer {
        await MainActor.run {
            PingIntentDependencies.sharedContainer
        }
    }

    static func nearestStation() async throws -> Stop? {
        let container = await container()
        guard let coordinate = await container.locationService.currentLocation() else {
            return nil
        }

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let stops = try await container.staticService.allStops()
        return stops.min { first, second in
            guard
                let firstCoordinate = first.coordinate,
                let secondCoordinate = second.coordinate
            else {
                return false
            }

            let firstDistance = CLLocation(
                latitude: firstCoordinate.latitude,
                longitude: firstCoordinate.longitude
            )
            .distance(from: userLocation)

            let secondDistance = CLLocation(
                latitude: secondCoordinate.latitude,
                longitude: secondCoordinate.longitude
            )
            .distance(from: userLocation)

            return firstDistance < secondDistance
        }
    }

#if canImport(AppIntents)
    static func donateNextDepartureIntent() async {
        do {
            try await NextDepartureIntent().donate()
        } catch {
            // Best-effort donation for Siri suggestions.
        }
    }
#endif
}
