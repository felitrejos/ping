import Foundation
import Observation

@MainActor
@Observable
public final class MakoStore {
    public var nextDeparture: LiveDeparture?
    public var nextCommute: CommutePlan?
    public var commutePlans: [CommutePlan] = []
    public var availableStops: [Stop] = []
    public var availableLines: [String] = []
    public var lineStops: [Stop] = []
    public var calendarAuthorization: CalendarAuthorizationState = .notDetermined
    public var isRefreshing = false
    public var lastUpdated: Date?
    public var lastErrorMessage: String?

    public var selectedLine: String = UserSettings.selectedLine() {
        didSet {
            UserSettings.setSelectedLine(selectedLine)
            Task { await reloadLineStops() }
        }
    }

    public var hasConfiguredRoute: Bool {
        UserSettings.homeStationID() != nil
    }

    public var hasConfiguredDestination: Bool {
        UserSettings.destinationStationID() != nil
    }

    public var hasConfiguredDefaultRoute: Bool {
        hasConfiguredRoute && hasConfiguredDestination
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
            if await calendarService.authorizationStatus() == .notDetermined {
                calendarAuthorization = await calendarService.requestAccess()
            }
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
            availableStops = try await staticService.allStops()
            availableLines = try await staticService.availableLines()
            await reloadLineStops()
            commutePlans = try await engine.commutePlans(within: 12)
            nextCommute = commutePlans.first
            nextDeparture = try await defaultBestDeparture()
            lastErrorMessage = nil
            lastUpdated = Date()
        } catch {
            lastErrorMessage = error.localizedDescription
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

    public func setDestinationStation(_ stopID: StopID?) async {
        await calendarService.setUserDestinationStation(stopID)
        await refresh()
    }

    public func selectedHomeStationID() async -> StopID? {
        await calendarService.userHomeStation()
    }

    public func selectedDestinationStationID() async -> StopID? {
        await calendarService.userDestinationStation()
    }

    private func defaultBestDeparture() async throws -> LiveDeparture? {
        guard
            let homeStopID = await calendarService.userHomeStation(),
            let destination = await calendarService.userDestinationStation()
        else {
            return nil
        }

        return try await engine.bestCatchableDeparture(from: homeStopID, to: destination)
    }

    private func reloadLineStops() async {
        do {
            lineStops = try await staticService.stopsForLine(selectedLine)
        } catch {
            lineStops = []
        }
    }
}
