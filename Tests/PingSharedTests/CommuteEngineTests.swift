import Foundation
import Testing
@testable import PingShared

struct CommuteEngineTests {
    @Test
    func picksLatestTrainThatStillArrivesBeforeEvent() async throws {
        // Event starts at 3_600. buffer=180, walk=480. Target arrival: 3_420.
        // TRIP_1 arrives 1_800, TRIP_2 arrives 2_300. Both fit, TRIP_2 is the
        // latest one we can still catch.
        let engine = makeEngine(delays: [:], now: Date(timeIntervalSince1970: 100))

        let plan = try await engine.nextCommute()

        #expect(plan != nil)
        #expect(plan?.trainOptions.count == 2)
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 1_140))
    }

    @Test
    func delayedLatestTrainShiftsRecommendedDeparture() async throws {
        let engine = makeEngine(
            delays: ["TRIP_2": ["ST_HOME": 300]],
            now: Date(timeIntervalSince1970: 100)
        )

        let plan = try await engine.nextCommute()

        #expect(plan?.trainOptions.count == 2)
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 1_440))
    }

    @Test
    func fallsBackToEarliestCatchableWhenNothingArrivesOnTime() async throws {
        // Every option arrives after the event starts, so there is no on-time
        // candidate. The engine should fall back to the earliest train we can
        // still catch instead of refusing to return a plan.
        let engine = makeEngine(
            departures: [
                TrainDeparture(
                    tripID: "TRIP_1",
                    departureTime: Date(timeIntervalSince1970: 4_000),
                    arrivalTime: Date(timeIntervalSince1970: 4_500),
                    headsign: "City",
                    routeShortName: "S1"
                ),
                TrainDeparture(
                    tripID: "TRIP_2",
                    departureTime: Date(timeIntervalSince1970: 5_000),
                    arrivalTime: Date(timeIntervalSince1970: 5_500),
                    headsign: "City",
                    routeShortName: "S1"
                ),
            ],
            delays: [:],
            now: Date(timeIntervalSince1970: 100)
        )

        let plan = try await engine.nextCommute()

        #expect(plan?.trainOptions.first?.tripID == "TRIP_1")
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 3_340))
    }

    @Test
    func missedTrainFallsForwardToNextOption() async throws {
        // TRIP_1 leave-by is already in the past. Engine should fall through to
        // TRIP_2 even though it is not the on-time latest candidate.
        let engine = makeEngine(
            departures: [
                TrainDeparture(
                    tripID: "TRIP_1",
                    departureTime: Date(timeIntervalSince1970: 700),
                    arrivalTime: Date(timeIntervalSince1970: 1_200),
                    headsign: "City",
                    routeShortName: "S1"
                ),
                TrainDeparture(
                    tripID: "TRIP_2",
                    departureTime: Date(timeIntervalSince1970: 1_400),
                    arrivalTime: Date(timeIntervalSince1970: 1_900),
                    headsign: "City",
                    routeShortName: "S1"
                ),
            ],
            delays: [:],
            now: Date(timeIntervalSince1970: 500)
        )

        let plan = try await engine.nextCommute()

        #expect(plan?.trainOptions.first?.tripID == "TRIP_1")
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 740))
    }
}

private func makeEngine(
    departures: [TrainDeparture] = [
        TrainDeparture(
            tripID: "TRIP_1",
            departureTime: Date(timeIntervalSince1970: 1_300),
            arrivalTime: Date(timeIntervalSince1970: 1_800),
            headsign: "City",
            routeShortName: "S1"
        ),
        TrainDeparture(
            tripID: "TRIP_2",
            departureTime: Date(timeIntervalSince1970: 1_800),
            arrivalTime: Date(timeIntervalSince1970: 2_300),
            headsign: "City",
            routeShortName: "S1"
        ),
    ],
    delays: [String: [StopID: Int]],
    now: Date
) -> CommuteEngine {
    CommuteEngine(
        staticService: EngineStaticService(departures: departures),
        realtimeService: MockRealtimeService(snapshot: RealtimeSnapshot(delaysByTripAndStop: delays)),
        calendarService: EngineCalendarService(),
        clock: FixedClock(now: now),
        walkingMinutesProvider: { 8 },
        bufferMinutesProvider: { 3 }
    )
}

private struct FixedClock: Clock {
    let now: Date
}

private actor EngineStaticService: StaticServiceProviding {
    let departures: [TrainDeparture]

    init(departures: [TrainDeparture]) {
        self.departures = departures
    }

    func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture] {
        departures.filter { $0.departureTime >= after }
    }

    func allStops() async throws -> [Stop] {
        []
    }

    func stopsForLine(_ lineName: String) async throws -> [Stop] {
        []
    }

    func searchStops(matching query: String) async throws -> [Stop] {
        []
    }

    func lineForRoute(origin: StopID, destination: StopID) async throws -> String? {
        "S1"
    }

    func routeStops(origin: StopID, destination: StopID) async throws -> [Stop] {
        []
    }

    func linesForStop(_ stopID: StopID) async throws -> [String] {
        []
    }
}

private actor EngineCalendarService: CalendarServiceProviding {
    func authorizationStatus() async -> CalendarAuthorizationState {
        .fullAccess
    }

    func requestAccess() async -> CalendarAuthorizationState {
        .fullAccess
    }

    func upcomingCommutes(within hours: Int) async throws -> [CommuteEvent] {
        [
            CommuteEvent(
                id: "event-1",
                title: "Office",
                startDate: Date(timeIntervalSince1970: 3_600),
                location: "City",
                resolvedStation: "ST_CITY"
            ),
        ]
    }

    func userHomeStation() async -> StopID? {
        "ST_HOME"
    }

    func setUserHomeStation(_ stopID: StopID?) async {}

    func userDestinationStation() async -> StopID? {
        "ST_CITY"
    }

    func setUserDestinationStation(_ stopID: StopID?) async {}
}
