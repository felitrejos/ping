import Foundation
import Testing
@testable import PingShared

@Suite(.serialized)
struct ServiceAlertsServiceTests {
    @Test
    func fetchAlertsParsesEnvelopeAndBuildsAlertMetadata() async throws {
        let feedURL = URL(string: "https://example.com/alerts/records")!
        let pbURL = URL(string: "https://example.com/alerts/feed.pb")!
        let now = UInt64(Date().timeIntervalSince1970)
        let session = URLSession.alertStubbed(with: [
            feedURL: .jsonRecords(fileURL: pbURL),
            pbURL: .protobuf(
                try makeAlertsFeedData(alerts: [
                    .init(
                        id: "ALERT_1",
                        title: "S2 delays",
                        details: "Minor service impact",
                        effect: .reducedService,
                        routeIDs: ["S2", "S1", "S2"],
                        start: now,
                        end: now + 600
                    )
                ])
            ),
        ])

        let service = FGCServiceAlertsService(feedURL: feedURL, session: session)
        let alerts = try await service.fetchAlerts()

        #expect(alerts.count == 1)
        #expect(alerts[0].id == "ALERT_1")
        #expect(alerts[0].title == "S2 delays")
        #expect(alerts[0].details == "Minor service impact")
        #expect(alerts[0].severity == .minor)
        #expect(alerts[0].affectedLines == ["S1", "S2"])
        #expect(alerts[0].startDate != nil)
        #expect(alerts[0].endDate != nil)
    }

    @Test
    func fetchAlertsSortsBySeverityDescending() async throws {
        let feedURL = URL(string: "https://example.com/alerts2/records")!
        let pbURL = URL(string: "https://example.com/alerts2/feed.pb")!
        let session = URLSession.alertStubbed(with: [
            feedURL: .jsonRecords(fileURL: pbURL),
            pbURL: .protobuf(
                try makeAlertsFeedData(alerts: [
                    .init(
                        id: "ALERT_INFO",
                        title: "Info notice",
                        details: "Informative update",
                        effect: .otherEffect,
                        routeIDs: ["S1"],
                        start: nil,
                        end: nil
                    ),
                    .init(
                        id: "ALERT_CLOSURE",
                        title: "S2 suspended",
                        details: "No service available",
                        effect: .noService,
                        routeIDs: ["S2"],
                        start: nil,
                        end: nil
                    ),
                ])
            ),
        ])

        let service = FGCServiceAlertsService(feedURL: feedURL, session: session)
        let alerts = try await service.fetchAlerts()

        #expect(alerts.count == 2)
        #expect(alerts[0].id == "ALERT_CLOSURE")
        #expect(alerts[0].severity == .closure)
        #expect(alerts[1].id == "ALERT_INFO")
        #expect(alerts[1].severity == .info)
    }
}

private struct AlertFixture {
    let id: String
    let title: String
    let details: String
    let effect: TransitRealtime_Alert.Effect
    let routeIDs: [String]
    let start: UInt64?
    let end: UInt64?
}

private func makeAlertsFeedData(alerts: [AlertFixture]) throws -> Data {
    var feed = TransitRealtime_FeedMessage()
    var header = TransitRealtime_FeedHeader()
    header.gtfsRealtimeVersion = "2.0"
    header.timestamp = UInt64(Date().timeIntervalSince1970)
    feed.header = header

    feed.entity = alerts.map { fixture in
        var entity = TransitRealtime_FeedEntity()
        entity.id = fixture.id

        var alert = TransitRealtime_Alert()
        alert.effect = fixture.effect

        var headerTranslation = TransitRealtime_TranslatedString.Translation()
        headerTranslation.text = fixture.title
        headerTranslation.language = "en"
        alert.headerText.translation = [headerTranslation]

        var descriptionTranslation = TransitRealtime_TranslatedString.Translation()
        descriptionTranslation.text = fixture.details
        descriptionTranslation.language = "en"
        alert.descriptionText.translation = [descriptionTranslation]

        alert.informedEntity = fixture.routeIDs.map { routeID in
            var informedEntity = TransitRealtime_EntitySelector()
            informedEntity.routeID = routeID
            return informedEntity
        }

        if fixture.start != nil || fixture.end != nil {
            var activePeriod = TransitRealtime_TimeRange()
            if let start = fixture.start {
                activePeriod.start = start
            }
            if let end = fixture.end {
                activePeriod.end = end
            }
            alert.activePeriod = [activePeriod]
        }

        entity.alert = alert
        return entity
    }

    return try feed.serializedData()
}

private enum AlertsStubbedResponse {
    case protobuf(Data)
    case jsonRecords(fileURL: URL)

    var body: Data {
        switch self {
        case let .protobuf(data):
            data
        case let .jsonRecords(fileURL):
            """
            {"results":[{"file":{"url":"\(fileURL.absoluteString)"}}]}
            """.data(using: .utf8) ?? Data()
        }
    }

    var contentType: String {
        switch self {
        case .protobuf:
            "application/octet-stream"
        case .jsonRecords:
            "application/json"
        }
    }
}

private final class AlertsURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [URL: AlertsStubbedResponse] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let response = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": response.contentType]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func alertStubbed(with responses: [URL: AlertsStubbedResponse]) -> URLSession {
        AlertsURLProtocolStub.responses = responses
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlertsURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
