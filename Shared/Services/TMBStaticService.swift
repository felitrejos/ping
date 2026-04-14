import Foundation
import ZIPFoundation

public actor TMBStaticService: TMBStaticServiceProviding {
    private struct ParsedCache: Sendable {
        let stopsByID: [String: TMBStop]
        let allStops: [TMBStop]
    }

    private var zipURL: URL?
    private var cache: ParsedCache?

    public init(zipURL: URL?) {
        self.zipURL = zipURL
    }

    public func updateZipURL(_ url: URL?) {
        guard zipURL != url else {
            return
        }

        zipURL = url
        cache = nil
    }

    public func invalidateCache() {
        cache = nil
    }

    public func allStops() async throws -> [TMBStop] {
        try loadCache().allStops
    }

    public func stops(in region: TMBBoundingBox) async throws -> [TMBStop] {
        try loadCache().allStops.filter { region.contains($0.coordinate) }
    }

    public func stop(id: String) async throws -> TMBStop? {
        try loadCache().stopsByID[id]
    }
}

// MARK: - Parsing
extension TMBStaticService {
    private func loadCache() throws -> ParsedCache {
        if let cache {
            return cache
        }

        guard let zipURL else {
            let emptyCache = ParsedCache(stopsByID: [:], allStops: [])
            cache = emptyCache
            return emptyCache
        }

        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            let emptyCache = ParsedCache(stopsByID: [:], allStops: [])
            cache = emptyCache
            return emptyCache
        }

        let archive = try Archive(url: zipURL, accessMode: .read)

        let stopsText = try readEntry(named: "stops.txt", from: archive)
        let stopsRows = try GTFSCSVParser.parse(text: stopsText)

        let parsedStops: [TMBStop] = stopsRows.compactMap { row in
            guard
                let stopID = normalized(row["stop_id"]),
                let stopName = normalized(row["stop_name"]),
                let latitudeRaw = row["stop_lat"],
                let longitudeRaw = row["stop_lon"]
            else {
                return nil
            }

            if row["location_type"] == "1" {
                return nil
            }

            guard
                let latitude = parseCoordinate(latitudeRaw),
                let longitude = parseCoordinate(longitudeRaw)
            else {
                return nil
            }

            return TMBStop(
                id: stopID,
                code: normalized(row["stop_code"]),
                name: stopName,
                coordinate: TransitCoordinate(latitude: latitude, longitude: longitude),
                routeShortNames: []
            )
        }

        let allStops = parsedStops.sorted { first, second in
            let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return first.id < second.id
        }
        let stopsByID = Dictionary(uniqueKeysWithValues: allStops.map { ($0.id, $0) })

        let parsedCache = ParsedCache(stopsByID: stopsByID, allStops: allStops)
        cache = parsedCache
        return parsedCache
    }

    private func readEntry(named name: String, from archive: Archive) throws -> String {
        let candidates = archive.filter { entry in
            entry.path == name || entry.path.hasSuffix("/\(name)")
        }
        guard let entry = candidates.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else {
            throw TMBStaticServiceError.missingEntry(name)
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }

        guard !data.isEmpty else {
            return ""
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw TMBStaticServiceError.invalidText(name)
        }

        return text
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseCoordinate(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum TMBStaticServiceError: Error, Equatable {
    case missingEntry(String)
    case invalidText(String)
}
