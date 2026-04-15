import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
public final class PingStore {
    public var nextDeparture: LiveDeparture?
    public var upcomingDepartures: [LiveDeparture] = []
    public var nextCommute: CommutePlan?
    public var commutePlans: [CommutePlan] = []
    public var availableStops: [Stop] = []
    public var lineStops: [Stop] = []
    public private(set) var favoriteStationIDs: [StopID] = UserSettings.favoriteStationIDs()
    public var activeServiceAlerts: [ServiceAlert] = []
    public var serviceAlertsLastUpdated: Date?
    public var calendarAuthorization: CalendarAuthorizationState = .notDetermined
    public var isRefreshing = false
    public var lastUpdated: Date?
    public var lastErrorMessage: String?
    public private(set) var userLocation: TransitCoordinate?
    public private(set) var homeStationID: StopID?
    public private(set) var destinationStationID: StopID?
    public private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    public private(set) var isTMBLayerPreferred = UserSettings.tmbEnabled()
    public private(set) var isFGCLayerPreferred = UserSettings.fgcEnabled()

    /// Dynamic walking ETA in minutes from current location to origin station.
    /// Returns 0 when location-based ETA is unavailable.
    public var walkingMinutes: Int {
        dynamicWalkingMinutes ?? 0
    }

    /// Whether the walking time is based on live location (true) or the manual fallback (false).
    public var isUsingLiveLocation: Bool {
        dynamicWalkingMinutes != nil
    }

    public var isLocationAccessDenied: Bool {
        locationAuthorizationStatus == .denied || locationAuthorizationStatus == .restricted
    }

    public var isLocationAccessGranted: Bool {
        #if os(macOS)
        locationAuthorizationStatus == .authorizedAlways || locationAuthorizationStatus == .authorized
        #else
        locationAuthorizationStatus == .authorizedAlways || locationAuthorizationStatus == .authorizedWhenInUse
        #endif
    }

    public private(set) var dynamicWalkingMinutes: Int?

    public var selectedLine: String = UserSettings.selectedLine() {
        didSet {
            UserSettings.setSelectedLine(selectedLine)
            Task { await reloadLineStops() }
        }
    }

    public var hasConfiguredRoute: Bool {
        homeStationID != nil
    }

    public var hasConfiguredDestination: Bool {
        destinationStationID != nil
    }

    public var hasConfiguredDefaultRoute: Bool {
        hasConfiguredRoute && hasConfiguredDestination
    }

    public var hasTMBCredentials: Bool {
        tmbCredentials?.hasAny ?? false
    }

    public var isTMBEnabled: Bool {
        hasTMBCredentials && isTMBLayerPreferred
    }

    public var favoriteStations: [Stop] {
        favoriteStationIDs.map { stopID in
            availableStops.first(where: { $0.id == stopID }) ?? Stop(id: stopID, name: stopID)
        }
    }

    private let engine: CommuteEngine
    private let staticService: StaticServiceProviding
    private let calendarService: CalendarServiceProviding
    private let realtimeService: RealtimeServiceProviding
    private let locationService: LocationProviding?
    private let walkingETAService: WalkingETAProviding?
    private let serviceAlertsService: ServiceAlertsProviding?
    private let tmbStaticService: TMBStaticServiceProviding?
    private let tmbRealtimeService: TMBRealtimeServiceProviding?
    private let tmbCredentials: TMBCredentialProvider?
    private let gtfsUpdateService: GTFSUpdateService?
    private let bundledGTFSURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var compatibleStopIDsCache: [StopID: Set<StopID>] = [:]

    public init(
        engine: CommuteEngine,
        staticService: StaticServiceProviding,
        calendarService: CalendarServiceProviding,
        realtimeService: RealtimeServiceProviding,
        locationService: LocationProviding? = nil,
        walkingETAService: WalkingETAProviding? = nil,
        serviceAlertsService: ServiceAlertsProviding? = nil,
        tmbStaticService: TMBStaticServiceProviding? = nil,
        tmbRealtimeService: TMBRealtimeServiceProviding? = nil,
        tmbCredentials: TMBCredentialProvider? = nil,
        gtfsUpdateService: GTFSUpdateService? = nil,
        bundledGTFSURL: URL? = nil
    ) {
        self.engine = engine
        self.staticService = staticService
        self.calendarService = calendarService
        self.realtimeService = realtimeService
        self.locationService = locationService
        self.walkingETAService = walkingETAService
        self.serviceAlertsService = serviceAlertsService
        self.tmbStaticService = tmbStaticService
        self.tmbRealtimeService = tmbRealtimeService
        self.tmbCredentials = tmbCredentials
        self.gtfsUpdateService = gtfsUpdateService
        self.bundledGTFSURL = bundledGTFSURL
        Task {
            calendarAuthorization = await calendarService.authorizationStatus()
        }
    }

    public func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            if await calendarService.authorizationStatus() == .notDetermined {
                calendarAuthorization = await calendarService.requestAccess()
            }
            await resetRouteForNewSession()
            requestLocationAccess(shouldRefreshAfterAuthorization: false)
            await checkForGTFSUpdate()
            await realtimeService.startPolling()
            await refresh()
            let stream = await realtimeService.updates()
            for await _ in stream {
                guard !Task.isCancelled else { break }
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        Task {
            await realtimeService.stopPolling()
        }
    }

    public func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            calendarAuthorization = await calendarService.authorizationStatus()
            homeStationID = await calendarService.userHomeStation()
            destinationStationID = await calendarService.userDestinationStation()
            locationAuthorizationStatus = locationService?.authorizationStatus() ?? .notDetermined
            favoriteStationIDs = UserSettings.favoriteStationIDs()
            availableStops = try await staticService.allStops()
            compatibleStopIDsCache.removeAll()
            await reloadLineStops()
            await updateWalkingETA()
            commutePlans = filterCommutesNearCurrentLocation(try await engine.commutePlans(within: 12))
            nextCommute = commutePlans.first
            (nextDeparture, upcomingDepartures) = try await defaultDepartures()
            await refreshServiceAlerts()
            lastErrorMessage = nil
            lastUpdated = Date()
        } catch {
            lastErrorMessage = error.localizedDescription
            upcomingDepartures = []
            lastUpdated = Date()
        }
    }

    public func requestCalendarAccess() async {
        calendarAuthorization = await calendarService.requestAccess()
        await refresh()
    }

    public func requestLocationAccess(shouldRefreshAfterAuthorization: Bool = true) {
        Task {
            let previousStatus = locationAuthorizationStatus
            await locationService?.requestAuthorization()
            locationAuthorizationStatus = locationService?.authorizationStatus() ?? .notDetermined
            guard shouldRefreshAfterAuthorization else {
                return
            }

            // Refresh when authorization changed, or when already authorized so location-dependent
            // features can update immediately.
            if locationAuthorizationStatus != previousStatus || isLocationAccessGranted {
                await refresh()
            }
        }
    }

    public func searchStops(matching query: String) async -> [Stop] {
        (try? await staticService.searchStops(matching: query)) ?? []
    }

    public func setHomeStation(_ stopID: StopID?) async {
        await calendarService.setUserHomeStation(stopID)
        homeStationID = stopID
        await autoDetectLine()
        await refresh()
    }

    public func setDestinationStation(_ stopID: StopID?) async {
        await calendarService.setUserDestinationStation(stopID)
        destinationStationID = stopID
        await autoDetectLine()
        await refresh()
    }

    public func setRoute(origin: StopID, destination: StopID) async {
        await calendarService.setUserHomeStation(origin)
        await calendarService.setUserDestinationStation(destination)
        homeStationID = origin
        destinationStationID = destination
        await autoDetectLine()
        await refresh()
    }

    public func refreshServiceAlerts() async {
        guard let serviceAlertsService else {
            activeServiceAlerts = []
            serviceAlertsLastUpdated = nil
            return
        }

        do {
            activeServiceAlerts = try await serviceAlertsService.fetchAlerts()
            serviceAlertsLastUpdated = Date()
        } catch {
            // Keep the previous snapshot and timestamp so UI can show stale state.
        }
    }

    public func setTMBEnabled(_ isEnabled: Bool) {
        isTMBLayerPreferred = isEnabled
        UserSettings.setTMBEnabled(isEnabled)
    }

    public func setFGCEnabled(_ isEnabled: Bool) {
        isFGCLayerPreferred = isEnabled
        UserSettings.setFGCEnabled(isEnabled)
    }

    public func tmbStops(in box: TMBBoundingBox) async -> [TMBStop] {
        guard hasTMBCredentials, let tmbStaticService else {
            return []
        }

        return (try? await tmbStaticService.stops(in: box)) ?? []
    }

    public func fgcStops(in box: TransitBoundingBox) async -> [Stop] {
        if let fgcStaticService = staticService as? FGCStaticService {
            return (try? await fgcStaticService.stops(in: box)) ?? []
        }

        return availableStops.filter { stop in
            guard let coordinate = stop.coordinate else {
                return false
            }
            return box.contains(coordinate)
        }
    }

    public func compatibleStopIDs(with stopID: StopID?) async -> Set<StopID> {
        let allStopIDs = Set(availableStops.map(\.id))
        guard let stopID, !stopID.isEmpty else {
            return allStopIDs
        }

        if let cached = compatibleStopIDsCache[stopID] {
            return cached
        }

        let compatibleFromStaticService: Set<StopID>
        if let fgcStaticService = staticService as? FGCStaticService {
            compatibleFromStaticService = (try? await fgcStaticService.compatibleStopIDs(for: stopID)) ?? []
        } else {
            compatibleFromStaticService = []
        }

        var compatible = compatibleFromStaticService.intersection(allStopIDs)
        if compatible.isEmpty {
            compatible = Set([stopID]).intersection(allStopIDs)
        }
        if compatible.isEmpty {
            compatible = allStopIDs
        }

        compatibleStopIDsCache[stopID] = compatible
        return compatible
    }

    public func tmbArrivals(for stop: TMBStop) async -> Result<[TMBArrival], TMBArrivalsError> {
        guard isTMBEnabled, let tmbRealtimeService else {
            return .failure(.noCredentials)
        }

        do {
            let identifier = stop.code ?? stop.id
            let arrivals = try await tmbRealtimeService.arrivals(stopID: identifier)
            return .success(arrivals)
        } catch let error as TMBArrivalsError {
            return .failure(error)
        } catch {
            return .failure(.network(error))
        }
    }

    public func fgcDepartures(from stopID: StopID, limit: Int = 6) async -> Result<[StationDeparture], FGCDeparturesError> {
        guard let fgcStaticService = staticService as? FGCStaticService else {
            return .failure(.unavailable)
        }

        do {
            let now = Date()
            let fetchLimit = max(limit * 4, limit)
            let scheduled = try await fgcStaticService.departuresFrom(origin: stopID, after: now, limit: fetchLimit)
            let departures = await scheduled.asyncMap { departure in
                let delaySeconds = await realtimeService.delayFor(tripID: departure.tripID, stopID: stopID) ?? 0
                let effectiveDeparture = departure.departureTime.addingTimeInterval(TimeInterval(delaySeconds))
                let minutes = max(0, Int((effectiveDeparture.timeIntervalSince(now) / 60.0).rounded(.awayFromZero)))
                return StationDeparture(
                    tripID: departure.tripID,
                    routeShortName: departure.routeShortName,
                    headsign: departure.headsign,
                    scheduledDepartureTime: departure.departureTime,
                    delaySeconds: delaySeconds,
                    minutesUntilDeparture: minutes
                )
            }
            let upcoming = departures
                .filter { $0.effectiveDepartureTime >= now }
                .sorted { $0.effectiveDepartureTime < $1.effectiveDepartureTime }
            return .success(Array(upcoming.prefix(max(0, limit))))
        } catch {
            return .failure(.requestFailed(error.localizedDescription))
        }
    }

    public func clearDefaultRoute() async {
        await calendarService.setUserHomeStation(nil)
        await calendarService.setUserDestinationStation(nil)
        homeStationID = nil
        destinationStationID = nil
        dynamicWalkingMinutes = nil
        nextDeparture = nil
        upcomingDepartures = []
        activeServiceAlerts = []
        await refresh()
    }

    public func addFavoriteStation(_ stopID: StopID) {
        guard UserSettings.isConfiguredStopID(stopID), !favoriteStationIDs.contains(stopID) else {
            return
        }

        favoriteStationIDs.append(stopID)
        UserSettings.setFavoriteStationIDs(favoriteStationIDs)
    }

    public func removeFavoriteStation(_ stopID: StopID) {
        favoriteStationIDs.removeAll { $0 == stopID }
        UserSettings.setFavoriteStationIDs(favoriteStationIDs)
    }

    public func moveFavoriteStations(fromOffsets: IndexSet, toOffset: Int) {
        favoriteStationIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        UserSettings.setFavoriteStationIDs(favoriteStationIDs)
    }

    private func autoDetectLine() async {
        guard
            let origin = await calendarService.userHomeStation(),
            let destination = await calendarService.userDestinationStation(),
            let line = try? await staticService.lineForRoute(origin: origin, destination: destination)
        else { return }
        selectedLine = line
    }

    public func selectedHomeStationID() async -> StopID? {
        if let homeStationID {
            return homeStationID
        }
        let fetchedHome = await calendarService.userHomeStation()
        homeStationID = fetchedHome
        return fetchedHome
    }

    public func selectedDestinationStationID() async -> StopID? {
        if let destinationStationID {
            return destinationStationID
        }
        let fetchedDestination = await calendarService.userDestinationStation()
        destinationStationID = fetchedDestination
        return fetchedDestination
    }

    private func defaultDepartures() async throws -> (best: LiveDeparture?, upcoming: [LiveDeparture]) {
        guard isUsingLiveLocation else {
            return (nil, [])
        }

        if homeStationID == nil {
            homeStationID = await calendarService.userHomeStation()
        }
        if destinationStationID == nil {
            destinationStationID = await calendarService.userDestinationStation()
        }

        guard let homeStopID = homeStationID, let destination = destinationStationID else {
            return (nil, [])
        }

        let candidates = try await engine.upcomingDepartures(from: homeStopID, to: destination, limit: 500)
        let now = Date()
        let leaveNowCutoff = now.addingTimeInterval(TimeInterval((walkingMinutes + UserSettings.bufferMinutes()) * 60))
        let horizon = now.addingTimeInterval(12 * 60 * 60)

        let upcoming = candidates
            .filter { $0.effectiveDepartureTime >= leaveNowCutoff && $0.effectiveDepartureTime <= horizon }
            .sorted { $0.effectiveDepartureTime < $1.effectiveDepartureTime }

        return (upcoming.first, upcoming)
    }

    private func updateWalkingETA() async {
        guard let locationService, let walkingETAService else {
            dynamicWalkingMinutes = nil
            return
        }

        guard let coordinate = await locationService.currentLocation() else {
            userLocation = nil
            dynamicWalkingMinutes = nil
            return
        }
        userLocation = TransitCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let resolvedHomeStationID: StopID?
        if let homeStationID {
            resolvedHomeStationID = homeStationID
        } else {
            resolvedHomeStationID = await calendarService.userHomeStation()
            homeStationID = resolvedHomeStationID
        }

        guard let homeStopID = resolvedHomeStationID,
              let homeStop = availableStops.first(where: { $0.id == homeStopID }) else {
            dynamicWalkingMinutes = nil
            return
        }

        dynamicWalkingMinutes = await walkingETAService.walkingMinutes(from: coordinate, to: homeStop)
    }

    private func filterCommutesNearCurrentLocation(_ plans: [CommutePlan]) -> [CommutePlan] {
        guard let userLocation else {
            return plans
        }

        return plans.filter { plan in
            guard
                let destinationID = plan.calendarEvent.resolvedStation,
                let destination = availableStops.first(where: { $0.id == destinationID }),
                let destinationCoordinate = destination.coordinate
            else {
                return true
            }

            return userLocation.distance(to: destinationCoordinate) > 800
        }
    }

    public func configuredRouteStops() async -> [Stop] {
        guard
            let origin = await calendarService.userHomeStation(),
            let destination = await calendarService.userDestinationStation()
        else {
            return []
        }

        return (try? await staticService.routeStops(origin: origin, destination: destination)) ?? []
    }

    private func checkForGTFSUpdate() async {
        guard let gtfsUpdateService else {
            return
        }

        if let bundledGTFSURL {
            let didUpdate = await gtfsUpdateService.updateIfNeeded()
            if didUpdate, let staticService = staticService as? FGCStaticService {
                let newURL = gtfsUpdateService.bestAvailableZipURL(bundledURL: bundledGTFSURL)
                await staticService.updateZipURL(newURL)
            }
        }

        guard
            let tmbCredentials,
            tmbCredentials.hasAny,
            let tmbStaticService = tmbStaticService as? TMBStaticService
        else {
            return
        }

        // Always sync the static service with any previously downloaded ZIP,
        // even when we do not fetch a new file this run.
        let existingURL = gtfsUpdateService.bestAvailableTMBZipURL()
        await tmbStaticService.updateZipURL(existingURL)

        let didUpdateTMB = await gtfsUpdateService.refreshTMBIfStale(credentials: tmbCredentials.ordered)
        let bestURL = gtfsUpdateService.bestAvailableTMBZipURL()
        await tmbStaticService.updateZipURL(bestURL)
        if didUpdateTMB {
            await tmbStaticService.invalidateCache()
        }
    }

    private func resetRouteForNewSession() async {
        await calendarService.setUserHomeStation(nil)
        await calendarService.setUserDestinationStation(nil)
        homeStationID = nil
        destinationStationID = nil
    }

    private func reloadLineStops() async {
        do {
            lineStops = try await staticService.stopsForLine(selectedLine)
        } catch {
            lineStops = []
        }
    }

}

private extension TransitCoordinate {
    func distance(to other: TransitCoordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

public enum FGCDeparturesError: Error, Equatable {
    case unavailable
    case requestFailed(String)

    public var displayMessage: String {
        switch self {
        case .unavailable:
            "FGC departures are unavailable."
        case let .requestFailed(message):
            message
        }
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: @Sendable (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self {
            let value = await transform(element)
            result.append(value)
        }
        return result
    }
}
