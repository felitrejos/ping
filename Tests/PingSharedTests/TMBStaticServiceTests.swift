import Foundation
import Testing
import ZIPFoundation
@testable import PingShared

struct TMBStaticServiceTests {
    @Test
    func parsesStopsAndRoutesFromGTFSZip() async throws {
        let zipURL = try makeTMBFixtureZip()
        let service = TMBStaticService(zipURL: zipURL)

        let allStops = try await service.allStops()
        #expect(allStops.count == 3)

        let stop = try #require(await service.stop(id: "STOP_1"))
        #expect(stop.name == "Placa Catalunya")
        #expect(stop.code == "1001")
        #expect(stop.routeShortNames == ["H12", "V17"])
    }

    @Test
    func filtersStopsByBoundingBox() async throws {
        let zipURL = try makeTMBFixtureZip()
        let service = TMBStaticService(zipURL: zipURL)
        let box = TMBBoundingBox(
            minLatitude: 41.3840,
            maxLatitude: 41.3910,
            minLongitude: 2.1650,
            maxLongitude: 2.1750
        )

        let stops = try await service.stops(in: box)

        #expect(stops.map(\.id).sorted() == ["STOP_1", "STOP_2"])
    }
}

private func makeTMBFixtureZip() throws -> URL {
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let zipURL = temporaryDirectory.appendingPathComponent("tmb_fixture.zip")
    let archive = try Archive(url: zipURL, accessMode: .create)

    let files = [
        "stops.txt": """
        stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type
        STOP_1,1001,Placa Catalunya,41.3874,2.1686,0
        STOP_2,1002,Passeig de Gracia,41.3902,2.1701,0
        STOP_3,1003,Sagrada Familia,41.4036,2.1744,0
        """,
        "routes.txt": """
        route_id,route_short_name
        ROUTE_1,H12
        ROUTE_2,V17
        ROUTE_3,47
        """,
        "trips.txt": """
        route_id,service_id,trip_id
        ROUTE_1,DAILY,TRIP_1
        ROUTE_2,DAILY,TRIP_2
        ROUTE_3,DAILY,TRIP_3
        """,
        "stop_times.txt": """
        trip_id,arrival_time,departure_time,stop_id,stop_sequence
        TRIP_1,08:00:00,08:00:00,STOP_1,1
        TRIP_1,08:05:00,08:05:00,STOP_2,2
        TRIP_2,08:02:00,08:02:00,STOP_1,1
        TRIP_3,08:10:00,08:10:00,STOP_3,1
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
