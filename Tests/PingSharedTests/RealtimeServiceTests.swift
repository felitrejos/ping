import Foundation
import Testing
@testable import PingShared

@Suite(.serialized)
struct RealtimeServiceTests {
    @Test
    func delayLookupReturnsParsedDepartureDelay() async throws {
        let feedURL = URL(string: "https://example.com/test1/records")!
        let pbURL = URL(string: "https://example.com/test1/feed.pb")!
        let session = URLSession.stubbed(with: [
            feedURL: .jsonRecords(fileURL: pbURL),
            pbURL: .protobuf(try makeFeedData(delay: 180)),
        ])
        let service = FGCRealtimeService(feedURL: feedURL, session: session, pollIntervalNanoseconds: 1_000_000)

        await service.refresh()
        let delay = await service.delayFor(tripID: "TRIP_1", stopID: "ST_HOME")

        #expect(delay == 180)
    }

    @Test
    func failedRefreshKeepsLastKnownSnapshot() async throws {
        let feedURL = URL(string: "https://example.com/test2/records")!
        let pbURL = URL(string: "https://example.com/test2/feed.pb")!
        let session = URLSession.stubbed(with: [
            feedURL: .jsonRecords(fileURL: pbURL),
            pbURL: .protobuf(try makeFeedData(delay: 240)),
        ])
        let service = FGCRealtimeService(feedURL: feedURL, session: session)
        await service.refresh()

        let failingSession = URLSession.stubbed(with: [:])
        let failingService = FGCRealtimeService(feedURL: Constants.fgcRealtimeFeedURL, session: failingSession)
        await failingService.refresh()

        let delay = await service.delayFor(tripID: "TRIP_1", stopID: "ST_HOME")
        #expect(delay == 240)
    }

    @Test
    func updateStreamEmitsSnapshot() async throws {
        let service = MockRealtimeService()
        let stream = await service.updates()
        let task = Task<[RealtimeSnapshot], Never> {
            var received: [RealtimeSnapshot] = []
            var iterator = stream.makeAsyncIterator()
            for _ in 0 ..< 2 {
                if let snapshot = await iterator.next() {
                    received.append(snapshot)
                }
            }
            return received
        }

        await service.setSnapshot(RealtimeSnapshot(delaysByTripAndStop: ["TRIP_1": ["ST_HOME": 120]]))

        let snapshots = await task.value
        #expect(snapshots.last?.delaysByTripAndStop["TRIP_1"]?["ST_HOME"] == 120)
    }
}

private func makeFeedData(delay: Int32) throws -> Data {
    var feed = TransitRealtime_FeedMessage()
    var header = TransitRealtime_FeedHeader()
    header.gtfsRealtimeVersion = "2.0"
    header.timestamp = UInt64(Date().timeIntervalSince1970)
    feed.header = header
    var entity = TransitRealtime_FeedEntity()
    entity.id = "1"

    var tripUpdate = TransitRealtime_TripUpdate()
    tripUpdate.trip.tripID = "TRIP_1"
    var stopTimeUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
    stopTimeUpdate.stopID = "ST_HOME"
    stopTimeUpdate.departure.delay = delay
    tripUpdate.stopTimeUpdate = [stopTimeUpdate]
    entity.tripUpdate = tripUpdate
    feed.entity = [entity]
    return try feed.serializedData()
}

