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

        guard let zipURL, FileManager.default.fileExists(atPath: zipURL.path) else {
            let emptyCache = ParsedCache(stopsByID: [:], allStops: [])
            cache = emptyCache
            return emptyCache
        }

        let archive = try Archive(url: zipURL, accessMode: .read)
        let stopsRows = try GTFSCSVParser.parse(text: try readEntry(named: "stops.txt", from: archive))
        let routesRows = try GTFSCSVParser.parse(text: try readEntry(named: "routes.txt", from: archive))
        let tripsRows = try GTFSCSVParser.parse(text: try readEntry(named: "trips.txt", from: archive))
        let stopTimesRows = try GTFSCSVParser.parse(text: try readEntry(named: "stop_times.txt", from: archive))

        let routeShortNameByRouteID: [String: String] = Dictionary(
            uniqueKeysWithValues: routesRows.compactMap { row in
                guard let routeID = row["route_id"] else {
                    return nil
                }

                let shortName = row["route_short_name"]
                    .flatMap(normalized)
                    ?? routeID
                return (routeID, shortName)
            }
        )

        let routeIDByTripID: [String: String] = Dictionary(
            uniqueKeysWithValues: tripsRows.compactMap { row in
                guard let tripID = row["trip_id"], let routeID = row["route_id"] else {
                    return nil
                }
                return (tripID, routeID)
            }
        )

        var routeShortNamesByStopID: [String: Set<String>] = [:]
        for row in stopTimesRows {
            guard
                let stopID = row["stop_id"],
                let tripID = row["trip_id"],
                let routeID = routeIDByTripID[tripID],
                let routeShortName = routeShortNameByRouteID[routeID]
            else {
                continue
            }
            routeShortNamesByStopID[stopID, default: []].insert(routeShortName)
        }

        let parsedStops: [TMBStop] = stopsRows.compactMap { row in
            guard
                let stopID = row["stop_id"],
                let stopName = row["stop_name"],
                let latitudeRaw = row["stop_lat"],
                let longitudeRaw = row["stop_lon"],
                let latitude = Double(latitudeRaw),
                let longitude = Double(longitudeRaw)
            else {
                return nil
            }

            if row["location_type"] == "1" {
                return nil
            }

            let routeShortNames = (routeShortNamesByStopID[stopID] ?? [])
                .sorted { first, second in
                    first.localizedStandardCompare(second) == .orderedAscending
                }

            return TMBStop(
                id: stopID,
                code: normalized(row["stop_code"]),
                name: stopName,
                coordinate: TransitCoordinate(latitude: latitude, longitude: longitude),
                routeShortNames: routeShortNames
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
        guard let entry = archive[name] else {
            throw TMBStaticServiceError.missingEntry(name)
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
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
}

public enum TMBStaticServiceError: Error, Equatable {
    case missingEntry(String)
    case invalidText(String)
}
