@preconcurrency import EventKit
import CoreLocation
import Foundation
import MapKit

public actor CalendarService: CalendarServiceProviding {
    private let eventProvider: any CalendarEventProviding
    private let locationResolver: any CalendarLocationResolving
    private let routeEstimator: any CalendarRouteEstimating
    private let staticService: StaticServiceProviding
    private let defaults: UserDefaults
    private var stationResolutionCache: [StationResolutionCacheKey: StationResolutionCacheValue] = [:]
    private let stationResolutionCacheTTL: TimeInterval = 20 * 60

    public init(
        eventProvider: any CalendarEventProviding = EventKitCalendarProvider(),
        locationResolver: any CalendarLocationResolving = MapKitCalendarLocationResolver(),
        routeEstimator: any CalendarRouteEstimating = MapKitCalendarRouteEstimator(),
        staticService: StaticServiceProviding,
        defaults: UserDefaults = .standard
    ) {
        self.eventProvider = eventProvider
        self.locationResolver = locationResolver
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
                    stationCandidateIDs: resolution.candidateStationIDs,
                    stationCandidatesDebug: resolution.candidateDebugLines
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
                candidateStationIDs: [],
                candidateDebugLines: ["No structured coordinate on event."]
            )
        }

        let cacheKey = StationResolutionCacheKey(coordinate: coordinate)
        if let cached = stationResolutionCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < stationResolutionCacheTTL {
            return .init(
                stationID: cached.stationID,
                candidateStationIDs: cached.candidateStationIDs,
                candidateDebugLines: cached.candidateDebugLines + ["(cached)"]
            )
        }

        let candidates = stops.closestCandidates(to: coordinate, maxDistance: 2_500, limit: 6)
        guard !candidates.isEmpty else {
            return .init(
                stationID: nil,
                candidateStationIDs: [],
                candidateDebugLines: ["No stations found within 2.5 km."]
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
        var debugLines: [String] = []
        if let resolvedStationID, let station = stops.first(where: { $0.id == resolvedStationID }) {
            debugLines.insert("Selected: \(station.name) (\(resolvedStationID))", at: 0)
        } else {
            debugLines.insert("Selected: none", at: 0)
        }
        for result in orderedResults {
            if let travelTime = result.travelTime {
                let walkMinutes = Int((travelTime / 60).rounded())
                debugLines.append("\(result.stop.name): \(walkMinutes)m (\(result.stop.id))")
            } else {
                debugLines.append("\(result.stop.name): no walking route (\(result.stop.id))")
            }
        }

        stationResolutionCache[cacheKey] = StationResolutionCacheValue(
            stationID: resolvedStationID,
            candidateStationIDs: candidateStationIDs,
            candidateDebugLines: debugLines,
            timestamp: Date()
        )
        return .init(
            stationID: resolvedStationID,
            candidateStationIDs: candidateStationIDs,
            candidateDebugLines: debugLines
        )
    }
}

public protocol CalendarLocationResolving: Sendable {
    func coordinate(for location: String, near stops: [Stop]) async -> TransitCoordinate?
}

public protocol CalendarRouteEstimating: Sendable {
    func walkingTravelTime(from source: TransitCoordinate, to destination: TransitCoordinate) async -> TimeInterval?
}

public struct MapKitCalendarLocationResolver: CalendarLocationResolving {
    public init() {}

    public func coordinate(for location: String, near stops: [Stop]) async -> TransitCoordinate? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location
        if let region = MKCoordinateRegion(stops: stops) {
            request.region = region
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            let coordinate: CLLocationCoordinate2D?
            if #available(macOS 26.0, iOS 26.0, *) {
                coordinate = response.mapItems.first?.location.coordinate
            } else {
                coordinate = response.mapItems.first?.placemark.coordinate
            }

            guard let coordinate else {
                return nil
            }

            return TransitCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            return nil
        }
    }
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
    let candidateDebugLines: [String]
    let timestamp: Date
}

private struct StationResolutionResult {
    let stationID: StopID?
    let candidateStationIDs: [StopID]
    let candidateDebugLines: [String]
}

public struct MapKitCalendarRouteEstimator: CalendarRouteEstimating {
    public init() {}

    public func walkingTravelTime(from source: TransitCoordinate, to destination: TransitCoordinate) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = .walking

        do {
            return try await MKDirections(request: request).calculate().routes.first?.expectedTravelTime
        } catch {
            return nil
        }
    }

    private func mapItem(for coordinate: TransitCoordinate) -> MKMapItem {
        MKMapItem(
            location: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            address: nil
        )
    }
}

private extension [Stop] {
    func closest(to coordinate: TransitCoordinate, maxDistance: CLLocationDistance) -> Stop? {
        let candidates = compactMap { stop -> (stop: Stop, distance: CLLocationDistance)? in
            guard let stopCoordinate = stop.coordinate else {
                return nil
            }

            let distance = stopCoordinate.distance(to: coordinate)
            return distance <= maxDistance ? (stop, distance) : nil
        }

        return candidates.min { $0.distance < $1.distance }?.stop
    }

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

private extension MKCoordinateRegion {
    init?(stops: [Stop]) {
        let coordinates = stops.compactMap(\.coordinate)
        guard !coordinates.isEmpty else {
            return nil
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? 41.387
        let maxLatitude = latitudes.max() ?? 41.387
        let minLongitude = longitudes.min() ?? 2.17
        let maxLongitude = longitudes.max() ?? 2.17
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) + 0.2, 0.2),
            longitudeDelta: max((maxLongitude - minLongitude) + 0.2, 0.2)
        )

        self.init(center: center, span: span)
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
