@preconcurrency import EventKit
import CoreLocation
import Foundation
import MapKit

public actor CalendarService: CalendarServiceProviding {
    private let eventProvider: any CalendarEventProviding
    private let routeEstimator: any CalendarRouteEstimating
    private let staticService: StaticServiceProviding
    private let defaults: UserDefaults
    private var stationResolutionCache: [StationResolutionCacheKey: StationResolutionCacheValue] = [:]
    private let stationResolutionCacheTTL: TimeInterval = 20 * 60

    public init(
        eventProvider: any CalendarEventProviding = EventKitCalendarProvider(),
        routeEstimator: any CalendarRouteEstimating = MapKitCalendarRouteEstimator(),
        staticService: StaticServiceProviding,
        defaults: UserDefaults = .standard
    ) {
        self.eventProvider = eventProvider
        self.routeEstimator = routeEstimator
        self.staticService = staticService
        self.defaults = defaults
    }

    public func authorizationStatus() async -> CalendarAuthorizationState {
        eventProvider.authorizationStatus()
    }

    public func requestAccess() async -> CalendarAuthorizationState {
        await eventProvider.requestAccess()
    }

    public func upcomingCommutes(within hours: Int) async throws -> [CommuteEvent] {
        let status = eventProvider.authorizationStatus()
        guard status.isAuthorized else {
            return []
        }

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(hours) * 3_600)
        let records = try await eventProvider.fetchEvents(from: startDate, to: endDate)
        let stops = try await staticService.allStops()

        var commutes: [CommuteEvent] = []
        for record in records
            .filter({ $0.coordinate != nil })
            .sorted(by: { $0.startDate < $1.startDate }) {
            let resolution = await resolveStation(
                coordinate: record.coordinate,
                from: stops
            )
            commutes.append(
                CommuteEvent(
                    id: record.id,
                    title: record.title,
                    startDate: record.startDate,
                    location: record.location,
                    resolvedStation: resolution.stationID,
                    stationCandidateIDs: resolution.candidateStationIDs
                )
            )
        }

        return commutes
    }

    public func userHomeStation() async -> StopID? {
        UserSettings.homeStationID(defaults: defaults)
    }

    public func setUserHomeStation(_ stopID: StopID?) async {
        UserSettings.setHomeStationID(stopID, defaults: defaults)
    }

    public func userDestinationStation() async -> StopID? {
        UserSettings.destinationStationID(defaults: defaults)
    }

    public func setUserDestinationStation(_ stopID: StopID?) async {
        UserSettings.setDestinationStationID(stopID, defaults: defaults)
    }

    private func resolveStation(
        coordinate: TransitCoordinate?,
        from stops: [Stop]
    ) async -> StationResolutionResult {
        guard let coordinate else {
            return .init(
                stationID: nil,
                candidateStationIDs: []
            )
        }

        let cacheKey = StationResolutionCacheKey(coordinate: coordinate)
        if let cached = stationResolutionCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < stationResolutionCacheTTL {
            return .init(
                stationID: cached.stationID,
                candidateStationIDs: cached.candidateStationIDs
            )
        }

        let candidates = stops.closestCandidates(to: coordinate, maxDistance: 2_500, limit: 6)
        guard !candidates.isEmpty else {
            return .init(
                stationID: nil,
                candidateStationIDs: []
            )
        }

        var stationResults: [(stop: Stop, travelTime: TimeInterval?, distanceOrder: Int)] = []

        for (index, candidate) in candidates.enumerated() {
            guard let stopCoordinate = candidate.coordinate else {
                continue
            }

            let travelTime = await routeEstimator.walkingTravelTime(from: coordinate, to: stopCoordinate)
            stationResults.append((stop: candidate, travelTime: travelTime, distanceOrder: index))
        }

        let orderedResults = stationResults.sorted { lhs, rhs in
            switch (lhs.travelTime, rhs.travelTime) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
                return lhs.distanceOrder < rhs.distanceOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.distanceOrder < rhs.distanceOrder
            }
        }

        let candidateStationIDs = orderedResults.map(\.stop.id)
        let resolvedStationID = orderedResults.first?.stop.id ?? candidates.first?.id

        stationResolutionCache[cacheKey] = StationResolutionCacheValue(
            stationID: resolvedStationID,
            candidateStationIDs: candidateStationIDs,
            timestamp: Date()
        )
        return .init(
            stationID: resolvedStationID,
            candidateStationIDs: candidateStationIDs
        )
    }
}

public protocol CalendarRouteEstimating: Sendable {
    func walkingTravelTime(from source: TransitCoordinate, to destination: TransitCoordinate) async -> TimeInterval?
}

private struct StationResolutionCacheKey: Hashable {
    let latitudeBucket: Int
    let longitudeBucket: Int

    init(coordinate: TransitCoordinate) {
        latitudeBucket = Int((coordinate.latitude * 10_000).rounded())
        longitudeBucket = Int((coordinate.longitude * 10_000).rounded())
    }
}

private struct StationResolutionCacheValue {
    let stationID: StopID?
    let candidateStationIDs: [StopID]
    let timestamp: Date
}

private struct StationResolutionResult {
    let stationID: StopID?
    let candidateStationIDs: [StopID]
}

public struct MapKitCalendarRouteEstimator: CalendarRouteEstimating {
    public init() {}

    public func walkingTravelTime(from source: TransitCoordinate, to destination: TransitCoordinate) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = .walking

        do {
            guard let route = try await MKDirections(request: request).calculate().routes.first else {
                return nil
            }
            return route.expectedTravelTime
        } catch {
            return nil
        }
    }

    private func mapItem(for coordinate: TransitCoordinate) -> MKMapItem {
        // iOS/macOS 26 deprecated the placemark-based initializer in favor of a
        // location + address pair. We don't have a postal address for an FGC stop
        // (and `MKDirections` doesn't need one for a walking-time query), so we
        // pass `nil` and let MapKit treat the coordinate as the source of truth.
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return MKMapItem(location: location, address: nil)
    }
}

private extension [Stop] {
    func closestCandidates(
        to coordinate: TransitCoordinate,
        maxDistance: CLLocationDistance,
        limit: Int
    ) -> [Stop] {
        compactMap { stop -> (stop: Stop, distance: CLLocationDistance)? in
            guard let stopCoordinate = stop.coordinate else {
                return nil
            }

            let distance = stopCoordinate.distance(to: coordinate)
            guard distance <= maxDistance else {
                return nil
            }

            return (stop, distance)
        }
        .sorted { $0.distance < $1.distance }
        .prefix(limit)
        .map(\.stop)
    }
}

private extension TransitCoordinate {
    func distance(to other: TransitCoordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

public final class EventKitCalendarProvider: @unchecked Sendable, CalendarEventProviding {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func authorizationStatus() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .fullAccess:
            .fullAccess
        case .writeOnly:
            .writeOnly
        @unknown default:
            .denied
        }
    }

    public func requestAccess() async -> CalendarAuthorizationState {
        do {
            if #available(macOS 14.0, iOS 17.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            return authorizationStatus()
        }

        return authorizationStatus()
    }

    public func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEventRecord] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).map { event in
            let coordinate = event.structuredLocation?.geoLocation.map { location in
                TransitCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }

            return CalendarEventRecord(
                id: event.calendarItemIdentifier,
                title: event.title,
                startDate: event.startDate,
                location: event.location,
                coordinate: coordinate
            )
        }
    }
}
