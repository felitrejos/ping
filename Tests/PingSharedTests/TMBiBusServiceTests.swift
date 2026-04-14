import Foundation
import Testing
@testable import PingShared

struct TMBiBusServiceTests {
    @Test
    func fallsBackToBackupCredentialsWhenPrimaryIsUnauthorized() async throws {
        let endpoint = URL(string: "https://example.com/v1/ibus/stops")!
        let primaryCredentials = TMBCredentials(appID: "primary-id", appKey: "primary-key")
        let backupCredentials = TMBCredentials(appID: "backup-id", appKey: "backup-key")
        let stopID = "1234"
        let primaryURL = makeStopURL(endpoint: endpoint, stopID: stopID, credentials: primaryCredentials)
        let backupURL = makeStopURL(endpoint: endpoint, stopID: stopID, credentials: backupCredentials)
        let arrivalsBody = Data(
            """
            {
              "features": [
                {
                  "properties": {
                    "line": "H10",
                    "destination": "Badal",
                    "t-in-s": 420
                  }
                }
              ]
            }
            """.utf8
        )

        let session = URLSession.stubbed(with: [
            primaryURL: .http(
                statusCode: 401,
                contentType: "application/json",
                body: Data("{}".utf8)
            ),
            backupURL: .http(
                statusCode: 200,
                contentType: "application/json",
                body: arrivalsBody
            ),
        ])

        let service = TMBiBusService(
            session: session,
            credentials: TMBCredentialProvider(primary: primaryCredentials, backup: backupCredentials),
            endpoint: endpoint
        )
        let arrivals = try await service.arrivals(stopID: stopID)

        #expect(arrivals.count == 1)
        #expect(arrivals.first?.routeShortName == "H10")
        #expect(arrivals.first?.destination == "Badal")
        #expect(arrivals.first?.minutesAway == 7)
    }

    @Test
    func throwsNoCredentialsWhenProviderHasNoKeys() async {
        let service = TMBiBusService(
            session: URLSession.stubbed(with: [:]),
            credentials: TMBCredentialProvider(primary: nil, backup: nil)
        )

        do {
            _ = try await service.arrivals(stopID: "1234")
            Issue.record("Expected noCredentials error.")
        } catch let error as TMBArrivalsError {
            guard case .noCredentials = error else {
                Issue.record("Expected noCredentials error.")
                return
            }
        } catch {
            Issue.record("Expected TMBArrivalsError.noCredentials.")
        }
    }
}

private func makeStopURL(endpoint: URL, stopID: String, credentials: TMBCredentials) -> URL {
    var components = URLComponents(
        url: endpoint.appendingPathComponent(stopID),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
        URLQueryItem(name: "app_id", value: credentials.appID),
        URLQueryItem(name: "app_key", value: credentials.appKey),
    ]
    return components.url!
}
