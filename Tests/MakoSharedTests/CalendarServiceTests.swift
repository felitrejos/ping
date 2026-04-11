import Foundation
import Testing
@testable import PingShared

struct CalendarServiceTests {
    @Test
    func upcomingCommutesResolvesStationFromLocation() async throws {
        let staticService = StubStaticService()
        let provider = StubCalendarProvider(
            status: .fullAccess,
            events: [
                CalendarEventRecord(
                    id: "event-1",
                    title: "Office",
                    startDate: Date(timeIntervalSince1970: 1000),
                    location: "Placa Catalunya office"
                ),
            ]
        )
        let service = CalendarService(eventProvider: provider, staticService: staticService)

        let commutes = try await service.upcomingCommutes(within: 2)

        #expect(commutes.first?.resolvedStation == "ST_CITY")
    }

    @Test
    func deniedAccessReturnsNoCommutes() async throws {
        let service = CalendarService(
            eventProvider: StubCalendarProvider(status: .denied, events: []),
            staticService: StubStaticService()
        )

        let commutes = try await service.upcomingCommutes(within: 2)

        #expect(commutes.isEmpty)
    }
}

private final class StubCalendarProvider: CalendarEventProviding {
    let status: CalendarAuthorizationState
    let events: [CalendarEventRecord]

    init(status: CalendarAuthorizationState, events: [CalendarEventRecord]) {
        self.status = status
        self.events = events
    }

    func authorizationStatus() -> CalendarAuthorizationState {
        status
    }

    func requestAccess() async -> CalendarAuthorizationState {
        status
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEventRecord] {
        events
    }
}

private actor StubStaticService: StaticServiceProviding {
    func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture] {
        []
    }

    func allStops() async throws -> [Stop] {
        [
            Stop(id: "ST_HOME", name: "Sant Cugat Centre"),
            Stop(id: "ST_CITY", name: "Placa Catalunya"),
        ]
    }

    func availableLines() async throws -> [String] {
        ["S1"]
    }

    func stopsForLine(_ lineName: String) async throws -> [Stop] {
        try await allStops()
    }

    func searchStops(matching query: String) async throws -> [Stop] {
        try await allStops()
    }
}
