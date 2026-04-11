import Foundation

public protocol StaticServiceProviding: Sendable {
    func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture]
    func allStops() async throws -> [Stop]
    func availableLines() async throws -> [String]
    func stopsForLine(_ lineName: String) async throws -> [Stop]
    func searchStops(matching query: String) async throws -> [Stop]
}

public protocol RealtimeServiceProviding: Sendable {
    func startPolling() async
    func stopPolling() async
    func refresh() async
    func delayFor(tripID: String, stopID: String) async -> Int?
    func updates() async -> AsyncStream<RealtimeSnapshot>
}

public protocol CalendarServiceProviding: Sendable {
    func authorizationStatus() async -> CalendarAuthorizationState
    func requestAccess() async -> CalendarAuthorizationState
    func upcomingCommutes(within hours: Int) async throws -> [CommuteEvent]
    func userHomeStation() async -> StopID?
    func setUserHomeStation(_ stopID: StopID?) async
    func userDestinationStation() async -> StopID?
    func setUserDestinationStation(_ stopID: StopID?) async
}

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }
}

public struct RealtimeSnapshot: Equatable, Sendable {
    public let delaysByTripAndStop: [String: [StopID: Int]]

    public init(delaysByTripAndStop: [String: [StopID: Int]]) {
        self.delaysByTripAndStop = delaysByTripAndStop
    }
}

public protocol CalendarEventProviding: Sendable {
    func authorizationStatus() -> CalendarAuthorizationState
    func requestAccess() async -> CalendarAuthorizationState
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEventRecord]
}
