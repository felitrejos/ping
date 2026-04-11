import Foundation
import Testing
@testable import MakoShared

struct CommuteEngineTests {
    @Test
    func nextCommuteUsesOnTimeDeparture() async throws {
        let engine = makeEngine(delays: [:], now: Date(timeIntervalSince1970: 100))

        let plan = try await engine.nextCommute()

        #expect(plan != nil)
        #expect(plan?.trainOptions.first?.delaySeconds == 0)
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 640))
    }

    @Test
    func delayedTrainShiftsRecommendedDeparture() async throws {
        let engine = makeEngine(delays: ["TRIP_1": ["ST_HOME": 300]], now: Date(timeIntervalSince1970: 100))

        let plan = try await engine.nextCommute()

        #expect(plan?.trainOptions.first?.delaySeconds == 300)
        #expect(plan?.recommendedDeparture == Date(timeIntervalSince1970: 940))
    }

    @Test
    func missedTrainFallsForwardToNextOption() async throws {
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

    func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture] {
        departures.filter { $0.departureTime >= after }
    }

    func allStops() async throws -> [Stop] {
        []
    }

    func searchStops(matching query: String) async throws -> [Stop] {
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
