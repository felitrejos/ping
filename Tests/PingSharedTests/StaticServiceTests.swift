import Foundation
import Testing
import ZIPFoundation
@testable import PingShared

struct StaticServiceTests {
    @Test
    func departuresBetweenJoinsTripsRoutesAndStops() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(
            zipURL: zipURL,
            calendar: makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let after = ISO8601DateFormatter().date(from: "2026-04-11T07:00:00Z")!
        let departures = try await service.departuresBetween(origin: "ST_HOME", destination: "ST_CITY", after: after)

        #expect(departures.count >= 1)
        #expect(departures.first?.tripID == "TRIP_1")
        #expect(departures.first?.headsign == "Placa Catalunya")
        #expect(departures.first?.routeShortName == "S1")
    }

    @Test
    func departuresBetweenSupportsPostMidnightTrips() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(
            zipURL: zipURL,
            calendar: makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let after = ISO8601DateFormatter().date(from: "2026-04-12T00:15:00Z")!
        let departures = try await service.departuresBetween(origin: "ST_HOME", destination: "ST_CITY", after: after)

        #expect(departures.first?.tripID == "TRIP_2")
        #expect(departures.first?.departureTime == ISO8601DateFormatter().date(from: "2026-04-12T01:15:00Z"))
    }

    @Test
    func searchStopsMatchesIgnoringCaseAndAccent() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(zipURL: zipURL)

        let matches = try await service.searchStops(matching: "catalunya")

        #expect(matches.contains(where: { $0.id == "ST_CITY" }))
    }

    @Test
    func routeStopsReturnsGtfsStationOrder() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(zipURL: zipURL)

        let stops = try await service.routeStops(origin: "ST_HOME", destination: "ST_CITY")

        #expect(stops.map(\.id) == ["ST_HOME", "ST_MID", "ST_CITY"])
        #expect(stops.compactMap(\.coordinate).count == 3)
    }

    @Test
    func departuresBetweenFiltersOutInactiveWeekdayService() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(
            zipURL: zipURL,
            calendar: makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        // Saturday morning. Weekday-only trip should not be active.
        let after = ISO8601DateFormatter().date(from: "2026-04-11T07:40:00Z")!
        let departures = try await service.departuresBetween(origin: "ST_HOME", destination: "ST_CITY", after: after)

        #expect(!departures.contains(where: { $0.tripID == "TRIP_WKD" }))
    }

    @Test
    func departuresBetweenAppliesCalendarDateExceptions() async throws {
        let zipURL = try makeFixtureZip()
        let service = FGCStaticService(
            zipURL: zipURL,
            calendar: makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        // Saturday morning. SPECIAL service is activated via calendar_dates.
        let after = ISO8601DateFormatter().date(from: "2026-04-11T08:30:00Z")!
        let departures = try await service.departuresBetween(origin: "ST_HOME", destination: "ST_CITY", after: after)

        #expect(departures.contains(where: { $0.tripID == "TRIP_SPECIAL" }))
    }
}

private func makeFixtureZip() throws -> URL {
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let zipURL = temporaryDirectory.appendingPathComponent("fixture.zip")
    let archive = try Archive(url: zipURL, accessMode: .create)

    let files = [
        "stops.txt": """
        stop_id,stop_name,stop_lat,stop_lon
        ST_HOME,Sant Cugat Centre,41.4700,2.0800
        ST_MID,Gracia,41.4000,2.1500
        ST_CITY,Placa Catalunya,41.3860,2.1700
        """,
        "routes.txt": """
        route_id,route_short_name
        ROUTE_1,S1
        """,
        "trips.txt": """
        route_id,service_id,trip_id,trip_headsign
        ROUTE_1,DAILY,TRIP_1,Placa Catalunya
        ROUTE_1,DAILY,TRIP_2,Placa Catalunya
        ROUTE_1,WKD,TRIP_WKD,Placa Catalunya
        ROUTE_1,SPECIAL,TRIP_SPECIAL,Placa Catalunya
        """,
        "stop_times.txt": """
        trip_id,arrival_time,departure_time,stop_id,stop_sequence
        TRIP_1,07:10:00,07:10:00,ST_HOME,1
        TRIP_1,07:25:00,07:25:00,ST_MID,2
        TRIP_1,07:35:00,07:35:00,ST_CITY,3
        TRIP_2,25:15:00,25:15:00,ST_HOME,1
        TRIP_2,25:30:00,25:30:00,ST_MID,2
        TRIP_2,25:40:00,25:40:00,ST_CITY,3
        TRIP_WKD,07:50:00,07:50:00,ST_HOME,1
        TRIP_WKD,08:05:00,08:05:00,ST_MID,2
        TRIP_WKD,08:15:00,08:15:00,ST_CITY,3
        TRIP_SPECIAL,09:00:00,09:00:00,ST_HOME,1
        TRIP_SPECIAL,09:15:00,09:15:00,ST_MID,2
        TRIP_SPECIAL,09:25:00,09:25:00,ST_CITY,3
        """,
        "calendar.txt": """
        service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
        DAILY,1,1,1,1,1,1,1,20260101,20261231
        WKD,1,1,1,1,1,0,0,20260101,20261231
        """,
        "calendar_dates.txt": """
        service_id,date,exception_type
        SPECIAL,20260411,1
        """,
    ]

    for (fileName, content) in files {
        let data = Data(content.utf8)
        try archive.addEntry(
            with: fileName,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let lowerBound = Int(position)
                let upperBound = lowerBound + size
                return data.subdata(in: lowerBound ..< upperBound)
            }
        )
    }

    return zipURL
}

private func makeCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}
