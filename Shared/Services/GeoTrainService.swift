import Foundation

public struct GeoTrainService: GeoTrainServiceProviding {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://fgc.opendatasoft.com/api/explore/v2.1/catalog/datasets/posicionament-dels-trens/records")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchUnits(limit: Int = 200) async throws -> [GeoTrainUnit] {
        // The OpenDataSoft v2.1 endpoint rejects high limits (e.g. 300) with HTTP 400.
        let targetLimit = String(max(1, min(limit, 100)))
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "limit" }
        queryItems.append(URLQueryItem(name: "limit", value: targetLimit))
        components?.queryItems = queryItems

        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawResults = root["results"] as? [[String: Any]]
        else {
            return []
        }

        return parseUnits(from: rawResults)
    }

    private func normalizedStopID(_ raw: String?) -> StopID? {
        guard let raw, !raw.isEmpty, raw != "NA" else {
            return nil
        }
        return raw
    }

    private func normalizedOnTime(_ raw: String?) -> Bool? {
        guard let raw else {
            return nil
        }

        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private func number(from value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func coordinate(from record: [String: Any]) -> TransitCoordinate? {
        if
            let geo = record["geo_point_2d"] as? [String: Any],
            let longitude = number(from: geo["lon"]),
            let latitude = number(from: geo["lat"])
        {
            return TransitCoordinate(latitude: latitude, longitude: longitude)
        }

        return nil
    }

    private func parseUnits(from records: [[String: Any]]) -> [GeoTrainUnit] {
        records.compactMap { record in
            guard
                let identifier = record["id"] as? String,
                let line = record["lin"] as? String,
                let coordinate = coordinate(from: record)
            else {
                return nil
            }

            return GeoTrainUnit(
                id: identifier,
                line: line,
                direction: (record["dir"] as? String) ?? "",
                originStopID: normalizedStopID(record["origen"] as? String),
                destinationStopID: normalizedStopID(record["desti"] as? String),
                coordinate: coordinate,
                isOnTime: normalizedOnTime(record["en_hora"] as? String)
            )
        }
    }
}
