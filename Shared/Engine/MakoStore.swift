import Foundation
import Observation

@MainActor
@Observable
public final class MakoStore {
    public var nextDeparture: LiveDeparture?
    public var nextCommute: CommutePlan?
    public var commutePlans: [CommutePlan] = []
    public var upcomingTrains: [LiveDeparture] = []
    public var availableStops: [Stop] = []
    public var filteredStops: [Stop] = []
    public var calendarAuthorization: CalendarAuthorizationState = .notDetermined
    public var isRefreshing = false
    public var lastUpdated: Date?
    public var stopSearchText = "" {
        didSet {
            Task {
                await reloadStopSearch()
            }
        }
    }

    private let engine: CommuteEngine
    private let staticService: StaticServiceProviding
    private let calendarService: CalendarServiceProviding
    private let realtimeService: RealtimeServiceProviding
    private var refreshTask: Task<Void, Never>?

    public init(
        engine: CommuteEngine,
        staticService: StaticServiceProviding,
        calendarService: CalendarServiceProviding,
        realtimeService: RealtimeServiceProviding
    ) {
        self.engine = engine
        self.staticService = staticService
        self.calendarService = calendarService
        self.realtimeService = realtimeService
        Task {
            calendarAuthorization = await calendarService.authorizationStatus()
        }
    }

    public func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            await realtimeService.startPolling()
            await refresh()
            let stream = await realtimeService.updates()
            for await _ in stream {
                await refresh()
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
            availableStops = try await staticService.allStops()
            filteredStops = try await staticService.searchStops(matching: stopSearchText)
            commutePlans = try await engine.commutePlans(within: 12)
            nextCommute = commutePlans.first
            nextDeparture = try await defaultNextDeparture()
            upcomingTrains = try await defaultUpcomingTrains()
            lastUpdated = Date()
        } catch {
            lastUpdated = Date()
        }
    }

    public func requestCalendarAccess() async {
        calendarAuthorization = await calendarService.requestAccess()
        await refresh()
    }

    public func setHomeStation(_ stopID: StopID?) async {
        await calendarService.setUserHomeStation(stopID)
        await refresh()
    }

    public func selectedHomeStationID() async -> StopID? {
        await calendarService.userHomeStation()
    }

    private func defaultNextDeparture() async throws -> LiveDeparture? {
        guard let homeStopID = await calendarService.userHomeStation() else {
            return nil
        }

        for destination in Constants.destinationStopIDs {
            if let departure = try await engine.nextDeparture(from: homeStopID, to: destination) {
                return departure
            }
        }

        return nil
    }

    private func defaultUpcomingTrains() async throws -> [LiveDeparture] {
        guard let homeStopID = await calendarService.userHomeStation() else {
            return []
        }

        var departures: [LiveDeparture] = []
        for destination in Constants.destinationStopIDs {
            departures.append(
                contentsOf: try await engine.upcomingDepartures(from: homeStopID, to: destination, limit: 5)
            )
        }

        return departures
            .sorted { $0.effectiveDepartureTime < $1.effectiveDepartureTime }
            .prefix(5)
            .map { $0 }
    }

    private func reloadStopSearch() async {
        do {
            filteredStops = try await staticService.searchStops(matching: stopSearchText)
        } catch {
            filteredStops = []
        }
    }
}
