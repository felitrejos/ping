import Foundation

public struct TMBiBusService: TMBRealtimeServiceProviding, Sendable {
    private let session: URLSession
    private let credentials: TMBCredentialProvider
    private let endpoint: URL
    private let decoder = JSONDecoder()

    public init(
        session: URLSession = .shared,
        credentials: TMBCredentialProvider,
        endpoint: URL = Constants.tmbIBusStopsBaseURL
    ) {
        self.session = session
        self.credentials = credentials
        self.endpoint = endpoint
    }

    public func arrivals(stopID: String) async throws -> [TMBArrival] {
        let availableCredentials = credentials.ordered
        guard !availableCredentials.isEmpty else {
            throw TMBArrivalsError.noCredentials
        }

        for credential in availableCredentials {
            let request = try makeRequest(stopID: stopID, credentials: credential)
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TMBArrivalsError.network(URLError(.badServerResponse))
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return try parseArrivals(data: data)
                }

                if [401, 403, 429].contains(httpResponse.statusCode) {
                    continue
                }

                throw TMBArrivalsError.network(URLError(.badServerResponse))
            } catch let error as TMBArrivalsError {
                throw error
            } catch let error as DecodingError {
                throw TMBArrivalsError.decoding(error)
            } catch {
                throw TMBArrivalsError.network(error)
            }
        }

        throw TMBArrivalsError.allKeysFailed
    }

    private func makeRequest(stopID: String, credentials: TMBCredentials) throws -> URLRequest {
        let stopURL = endpoint.appendingPathComponent(stopID)
        guard var components = URLComponents(url: stopURL, resolvingAgainstBaseURL: false) else {
            throw TMBArrivalsError.network(URLError(.badURL))
        }
        components.queryItems = [
            URLQueryItem(name: "app_id", value: credentials.appID),
            URLQueryItem(name: "app_key", value: credentials.appKey),
        ]

        guard let url = components.url else {
            throw TMBArrivalsError.network(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func parseArrivals(data: Data) throws -> [TMBArrival] {
        let response = try decoder.decode(APIResponse.self, from: data)
        let features = response.features
            ?? response.data?.features
            ?? response.ibus
            ?? response.data?.ibus
            ?? []
        let now = Date()

        let arrivals = features.compactMap { feature -> TMBArrival? in
            let payload = feature.properties ?? feature.asProperties
            guard let payload else {
                return nil
            }

            let route = payload.line?.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = payload.destination?.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondsAway = payload.secondsUntilArrival?.value
            guard
                let route,
                !route.isEmpty,
                let destination,
                !destination.isEmpty,
                let secondsAway
            else {
                return nil
            }

            let clampedSeconds = max(0, secondsAway)
            let minutesAway = Int(ceil(Double(clampedSeconds) / 60))
            return TMBArrival(
                routeShortName: route,
                destination: destination,
                arrivalDate: now.addingTimeInterval(TimeInterval(clampedSeconds)),
                minutesAway: minutesAway,
                isRealtime: true
            )
        }

        return arrivals.sorted { first, second in
            if first.arrivalDate == second.arrivalDate {
                return first.routeShortName < second.routeShortName
            }
            return first.arrivalDate < second.arrivalDate
        }
    }
}

public enum TMBArrivalsError: Error, Sendable {
    case noCredentials
    case allKeysFailed
    case network(Error)
    case decoding(Error)

    public var displayMessage: String {
        switch self {
        case .noCredentials:
            "TMB API credentials are missing."
        case .allKeysFailed:
            "Couldn't load arrivals right now."
        case .network:
            "Network error while loading arrivals."
        case .decoding:
            "Received an unexpected arrivals payload."
        }
    }
}

private struct APIResponse: Decodable {
    let features: [APIFeature]?
    let data: APIData?
    let ibus: [APIFeature]?
}

private struct APIData: Decodable {
    let features: [APIFeature]?
    let ibus: [APIFeature]?
}

private struct APIFeature: Decodable {
    let properties: APIProperties?
    let line: StringOrInt?
    let destination: String?
    let secondsUntilArrival: IntOrString?

    enum CodingKeys: String, CodingKey {
        case properties
        case line
        case destination
        case secondsUntilArrival = "t-in-s"
    }

    var asProperties: APIProperties? {
        APIProperties(
            line: line,
            destination: destination,
            secondsUntilArrival: secondsUntilArrival
        )
    }
}

private struct APIProperties: Decodable {
    let line: StringOrInt?
    let destination: String?
    let secondsUntilArrival: IntOrString?

    enum CodingKeys: String, CodingKey {
        case line
        case destination
        case secondsUntilArrival = "t-in-s"
    }
}

private struct StringOrInt: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
            return
        }

        if let int = try? container.decode(Int.self) {
            value = String(int)
            return
        }

        if let double = try? container.decode(Double.self) {
            if double.rounded() == double {
                value = String(Int(double))
            } else {
                value = String(double)
            }
            return
        }

        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string-compatible value."
            )
        )
    }
}

private struct IntOrString: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
            return
        }

        if let double = try? container.decode(Double.self) {
            value = Int(double.rounded())
            return
        }

        if
            let string = try? container.decode(String.self),
            let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            value = int
            return
        }

        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected int-compatible value."
            )
        )
    }
}
