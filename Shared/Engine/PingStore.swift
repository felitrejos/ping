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
    public var configuredRouteStopsList: [Stop] = []
    public var availableStops: [Stop] = []
    public var availableLines: [String] = []
    public var lineStops: [Stop] = []
    public private(set) var favoriteStationIDs: [StopID] = UserSettings.favoriteStationIDs()
    public var geoTrainUnits: [GeoTrainUnit] = []
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

    public var favoriteStations: [Stop] {
        favoriteStationIDs.compactMap { stopID in
            availableStops.first(where: { $0.id == stopID })
        }
    }

    private let engine: CommuteEngine
    private let staticService: StaticServiceProviding
    private let calendarService: CalendarServiceProviding
    private let realtimeService: RealtimeServiceProviding
    private let locationService: LocationProviding?
    private let walkingETAService: WalkingETAProviding?
    private let geoTrainService: GeoTrainServiceProviding?
    private let serviceAlertsService: ServiceAlertsProviding?
    private let gtfsUpdateService: GTFSUpdateService?
    private let bundledGTFSURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var didAutoSelectClosestOriginThisSession = false

    public init(
        engine: CommuteEngine,
        staticService: StaticServiceProviding,
        calendarService: CalendarServiceProviding,
        realtimeService: RealtimeServiceProviding,
        locationService: LocationProviding? = nil,
        walkingETAService: WalkingETAProviding? = nil,
        geoTrainService: GeoTrainServiceProviding? = nil,
        serviceAlertsService: ServiceAlertsProviding? = nil,
        gtfsUpdateService: GTFSUpdateService? = nil,
        bundledGTFSURL: URL? = nil
    ) {
        self.engine = engine
        self.staticService = staticService
        self.calendarService = calendarService
        self.realtimeService = realtimeService
        self.locationService = locationService
        self.walkingETAService = walkingETAService
        self.geoTrainService = geoTrainService
        self.serviceAlertsService = serviceAlertsService
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
            requestLocationAccess()
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
            availableLines = try await staticService.availableLines()
            await reloadLineStops()
            await updateWalkingETA()
            commutePlans = filterCommutesNearCurrentLocation(try await engine.commutePlans(within: 12))
            nextCommute = commutePlans.first
            nextDeparture = try await defaultBestDeparture()
            upcomingDepartures = try await defaultUpcomingDepartures()
            configuredRouteStopsList = await configuredRouteStops()
            await refreshGeoTrainUnits()
            await refreshServiceAlerts()
            lastErrorMessage = nil
            lastUpdated = Date()
        } catch {
            lastErrorMessage = error.localizedDescription
            upcomingDepartures = []
            configuredRouteStopsList = []
            geoTrainUnits = []
            lastUpdated = Date()
        }
    }

    public func resetClosestOriginSelectionForCurrentSession() {
        didAutoSelectClosestOriginThisSession = false
    }

    public func requestCalendarAccess() async {
        calendarAuthorization = await calendarService.requestAccess()
        await refresh()
    }

    public func requestLocationAccess() {
        Task {
            await locationService?.requestAuthorization()
            locationAuthorizationStatus = locationService?.authorizationStatus() ?? .notDetermined
            await refresh()
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

    public func refreshGeoTrainUnits() async {
        guard let geoTrainService else {
            geoTrainUnits = []
            return
        }

        do {
            geoTrainUnits = try await geoTrainService.fetchUnits(limit: 100)
        } catch {
            geoTrainUnits = []
        }
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

    public func clearDefaultRoute() async {
        await calendarService.setUserHomeStation(nil)
        await calendarService.setUserDestinationStation(nil)
        homeStationID = nil
        destinationStationID = nil
        // Avoid immediately re-selecting nearest origin right after manual clear.
        didAutoSelectClosestOriginThisSession = true
        dynamicWalkingMinutes = nil
        nextDeparture = nil
        upcomingDepartures = []
        configuredRouteStopsList = []
        geoTrainUnits = []
        activeServiceAlerts = []
        await refresh()
    }

    public func isFavoriteStation(_ stopID: StopID) -> Bool {
        favoriteStationIDs.contains(stopID)
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

    public func toggleFavoriteStation(_ stopID: StopID) {
        if isFavoriteStation(stopID) {
            removeFavoriteStation(stopID)
        } else {
            addFavoriteStation(stopID)
        }
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

    private func defaultBestDeparture() async throws -> LiveDeparture? {
        guard isUsingLiveLocation else {
            return nil
        }

        let resolvedHomeStationID: StopID?
        if let homeStationID {
            resolvedHomeStationID = homeStationID
        } else {
            resolvedHomeStationID = await calendarService.userHomeStation()
        }

        let resolvedDestinationStationID: StopID?
        if let destinationStationID {
            resolvedDestinationStationID = destinationStationID
        } else {
            resolvedDestinationStationID = await calendarService.userDestinationStation()
        }

        homeStationID = resolvedHomeStationID
        destinationStationID = resolvedDestinationStationID

        guard let homeStopID = resolvedHomeStationID, let destination = resolvedDestinationStationID else {
            return nil
        }

        return try await engine.bestCatchableDeparture(from: homeStopID, to: destination)
    }

    private func defaultUpcomingDepartures() async throws -> [LiveDeparture] {
        guard isUsingLiveLocation else {
            return []
        }

        let resolvedHomeStationID: StopID?
        if let homeStationID {
            resolvedHomeStationID = homeStationID
        } else {
            resolvedHomeStationID = await calendarService.userHomeStation()
        }

        let resolvedDestinationStationID: StopID?
        if let destinationStationID {
            resolvedDestinationStationID = destinationStationID
        } else {
            resolvedDestinationStationID = await calendarService.userDestinationStation()
        }

        homeStationID = resolvedHomeStationID
        destinationStationID = resolvedDestinationStationID

        guard let homeStopID = resolvedHomeStationID, let destination = resolvedDestinationStationID else {
            return []
        }

        let candidates = try await engine.upcomingDepartures(from: homeStopID, to: destination, limit: 500)
        let now = Date()
        let leaveNowCutoff = now.addingTimeInterval(TimeInterval((walkingMinutes + UserSettings.bufferMinutes()) * 60))
        let horizon = now.addingTimeInterval(12 * 60 * 60)

        return candidates
            .filter { departure in
                departure.effectiveDepartureTime >= leaveNowCutoff &&
                    departure.effectiveDepartureTime <= horizon
            }
            .sorted { $0.effectiveDepartureTime < $1.effectiveDepartureTime }
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
        await autoSelectClosestOriginIfNeeded()

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

    private func autoSelectClosestOriginIfNeeded() async {
        guard
            UserSettings.autoSelectClosestOrigin(),
            !didAutoSelectClosestOriginThisSession,
            let userLocation,
            let closestStop = availableStops.closest(to: userLocation)
        else {
            return
        }

        await calendarService.setUserHomeStation(closestStop.id)
        homeStationID = closestStop.id
        didAutoSelectClosestOriginThisSession = true
        await autoDetectLine()
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
        guard let gtfsUpdateService, let bundledGTFSURL else { return }
        let didUpdate = await gtfsUpdateService.updateIfNeeded()
        if didUpdate, let staticService = staticService as? FGCStaticService {
            let newURL = gtfsUpdateService.bestAvailableZipURL(bundledURL: bundledGTFSURL)
            await staticService.updateZipURL(newURL)
        }
    }

    private func reloadLineStops() async {
        do {
            lineStops = try await staticService.stopsForLine(selectedLine)
        } catch {
            lineStops = []
        }
    }

}

private extension [Stop] {
    func closest(to coordinate: TransitCoordinate) -> Stop? {
        filter { $0.coordinate != nil }
            .min { first, second in
                first.distanceSquared(to: coordinate) < second.distanceSquared(to: coordinate)
            }
    }
}

private extension Stop {
    func distanceSquared(to other: TransitCoordinate) -> Double {
        guard let coordinate else {
            return .greatestFiniteMagnitude
        }

        let latitudeDelta = coordinate.latitude - other.latitude
        let longitudeDelta = coordinate.longitude - other.longitude
        return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
    }
}

private extension TransitCoordinate {
    func distance(to other: TransitCoordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
