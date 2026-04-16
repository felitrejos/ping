import Foundation
import ZIPFoundation

public actor TMBStaticService: TMBStaticServiceProviding {
    private struct TMBStopTime: Sendable {
        let tripID: String
        let arrivalSeconds: Int
    }

    private struct TMBTrip: Sendable {
        let id: String
        let routeID: String
        let serviceID: String
        let headsignKey: String
    }

    private struct TMBRoute: Sendable {
        let id: String
        let shortNameKey: String
    }

    private struct TMBServiceCalendar: Sendable {
        let serviceID: String
        let startDayKey: Int
        let endDayKey: Int
        let activeWeekdays: Set<Int>

        func isActive(dayKey: Int, weekday: Int) -> Bool {
            dayKey >= startDayKey && dayKey <= endDayKey && activeWeekdays.contains(weekday)
        }
    }

    private enum TMBServiceExceptionType: Int, Sendable {
        case added = 1
        case removed = 2
    }

    private struct ParsedCache: Sendable {
        let stopsByID: [String: TMBStop]
        let allStops: [TMBStop]
        let stopSpatialIndex: TMBStopSpatialIndex
        let stopTimesByStopID: [String: [TMBStopTime]]
        let tripsByID: [String: TMBTrip]
        let routesByID: [String: TMBRoute]
        let serviceCalendars: [String: TMBServiceCalendar]
        let serviceExceptions: [Int: [String: TMBServiceExceptionType]]
    }

    private struct GridCellKey: Hashable, Sendable {
        let latitudeIndex: Int
        let longitudeIndex: Int
    }

    private struct TMBStopSpatialIndex: Sendable {
        private let cellSize: Double
        private let stopsByCell: [GridCellKey: [TMBStop]]

        init(stops: [TMBStop], cellSize: Double = 0.01) {
            self.cellSize = cellSize

            var buckets: [GridCellKey: [TMBStop]] = [:]
            for stop in stops {
                let key = GridCellKey(
                    latitudeIndex: Self.bucketIndex(for: stop.coordinate.latitude, cellSize: cellSize),
                    longitudeIndex: Self.bucketIndex(for: stop.coordinate.longitude, cellSize: cellSize)
                )
                buckets[key, default: []].append(stop)
            }
            stopsByCell = buckets
        }

        func stops(in region: TMBBoundingBox) -> [TMBStop] {
            let minLatitudeIndex = Self.bucketIndex(for: region.minLatitude, cellSize: cellSize)
            let maxLatitudeIndex = Self.bucketIndex(for: region.maxLatitude, cellSize: cellSize)
            let minLongitudeIndex = Self.bucketIndex(for: region.minLongitude, cellSize: cellSize)
            let maxLongitudeIndex = Self.bucketIndex(for: region.maxLongitude, cellSize: cellSize)

            var result: [TMBStop] = []
            for latitudeIndex in minLatitudeIndex ... maxLatitudeIndex {
                for longitudeIndex in minLongitudeIndex ... maxLongitudeIndex {
                    let key = GridCellKey(latitudeIndex: latitudeIndex, longitudeIndex: longitudeIndex)
                    guard let bucket = stopsByCell[key] else {
                        continue
                    }
                    result.append(contentsOf: bucket)
                }
            }

            return result.filter { region.contains($0.coordinate) }
        }

        private static func bucketIndex(for coordinate: Double, cellSize: Double) -> Int {
            Int(floor(coordinate / cellSize))
        }
    }

    private var zipURL: URL?
    private var cache: ParsedCache?
    private let calendar = Calendar(identifier: .gregorian)

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
        let filtered = try loadCache().stopSpatialIndex.stops(in: region)
        return filtered.sorted { first, second in
            let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return first.id < second.id
        }
    }

    public func stop(id: String) async throws -> TMBStop? {
        try loadCache().stopsByID[id]
    }

    /// Finds the scheduled arrival time closest to `target` at `stopID` for a trip whose route
    /// short name matches `routeShortName` (case/diacritic-insensitive) and whose headsign loosely
    /// matches `destination`. Returns `nil` when the static GTFS isn't loaded, no match is found,
    /// or no candidate falls within `window`.
    public func scheduledArrival(
        stopID: String,
        routeShortName: String,
        destination: String?,
        target: Date,
        window: TimeInterval = 30 * 60
    ) -> Date? {
        guard let cache = try? loadCache(), !cache.stopTimesByStopID.isEmpty else {
            return nil
        }

        guard let stopTimes = cache.stopTimesByStopID[stopID], !stopTimes.isEmpty else {
            return nil
        }

        let routeKey = normalizedKey(routeShortName)
        let destinationKey = destination.map(normalizedKey) ?? ""

        var bestDate: Date?
        var bestDelta: TimeInterval = .greatestFiniteMagnitude

        for serviceDay in candidateServiceDays(for: target) {
            guard let dayKey = dayKey(for: serviceDay) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: serviceDay)

            for stopTime in stopTimes {
                guard
                    let trip = cache.tripsByID[stopTime.tripID],
                    let route = cache.routesByID[trip.routeID]
                else {
                    continue
                }

                guard route.shortNameKey == routeKey else {
                    continue
                }

                if !destinationKey.isEmpty, !trip.headsignKey.isEmpty {
                    let matches = trip.headsignKey == destinationKey
                        || trip.headsignKey.contains(destinationKey)
                        || destinationKey.contains(trip.headsignKey)
                    if !matches {
                        continue
                    }
                }

                if !tripRuns(on: serviceDay, dayKey: dayKey, weekday: weekday, serviceID: trip.serviceID, cache: cache) {
                    continue
                }

                let candidate = serviceDay.addingTimeInterval(TimeInterval(stopTime.arrivalSeconds))
                let delta = abs(candidate.timeIntervalSince(target))
                if delta <= window && delta < bestDelta {
                    bestDelta = delta
                    bestDate = candidate
                }
            }
        }

        return bestDate
    }

    private func tripRuns(
        on serviceDay: Date,
        dayKey: Int,
        weekday: Int,
        serviceID: String,
        cache: ParsedCache
    ) -> Bool {
        if let exception = cache.serviceExceptions[dayKey]?[serviceID] {
            switch exception {
            case .added:
                return true
            case .removed:
                return false
            }
        }

        guard let service = cache.serviceCalendars[serviceID] else {
            // If no calendar exists, assume the service runs every weekday within the whole feed
            // window. This avoids hiding every arrival when a feed omits calendar.txt entirely.
            return !cache.serviceCalendars.isEmpty ? false : true
        }

        return service.isActive(dayKey: dayKey, weekday: weekday)
    }

    private func candidateServiceDays(for date: Date) -> [Date] {
        let startOfToday = calendar.startOfDay(for: date)
        guard
            let previous = calendar.date(byAdding: .day, value: -1, to: startOfToday),
            let next = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else {
            return [startOfToday]
        }
        return [previous, startOfToday, next]
    }

    private func dayKey(for date: Date) -> Int? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return nil
        }

        return year * 10_000 + month * 100 + day
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Parsing
extension TMBStaticService {
    private func loadCache() throws -> ParsedCache {
        if let cache {
            return cache
        }

        let emptyCache = ParsedCache(
            stopsByID: [:],
            allStops: [],
            stopSpatialIndex: TMBStopSpatialIndex(stops: []),
            stopTimesByStopID: [:],
            tripsByID: [:],
            routesByID: [:],
            serviceCalendars: [:],
            serviceExceptions: [:]
        )

        guard let zipURL else {
            cache = emptyCache
            return emptyCache
        }

        guard FileManager.default.fileExists(atPath: zipURL.path) else {
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

        let routesByID = parseRoutes(archive: archive)
        let tripsByID = parseTrips(archive: archive)
        let stopTimesByStopID = parseStopTimes(archive: archive)
        let (serviceCalendars, serviceExceptions) = parseCalendar(archive: archive)

        let parsedCache = ParsedCache(
            stopsByID: stopsByID,
            allStops: allStops,
            stopSpatialIndex: TMBStopSpatialIndex(stops: allStops),
            stopTimesByStopID: stopTimesByStopID,
            tripsByID: tripsByID,
            routesByID: routesByID,
            serviceCalendars: serviceCalendars,
            serviceExceptions: serviceExceptions
        )
        cache = parsedCache
        return parsedCache
    }

    private func parseRoutes(archive: Archive) -> [String: TMBRoute] {
        guard let rows = try? parseOptionalRows(named: "routes.txt", from: archive), !rows.isEmpty else {
            return [:]
        }

        var result: [String: TMBRoute] = [:]
        for row in rows {
            guard let routeID = normalized(row["route_id"]) else {
                continue
            }

            let rawName = normalized(row["route_short_name"]) ?? routeID
            result[routeID] = TMBRoute(id: routeID, shortNameKey: normalizedKey(rawName))
        }
        return result
    }

    private func parseTrips(archive: Archive) -> [String: TMBTrip] {
        guard let rows = try? parseOptionalRows(named: "trips.txt", from: archive), !rows.isEmpty else {
            return [:]
        }

        var result: [String: TMBTrip] = [:]
        for row in rows {
            guard
                let tripID = normalized(row["trip_id"]),
                let routeID = normalized(row["route_id"])
            else {
                continue
            }

            let headsign = normalized(row["trip_headsign"]) ?? normalized(row["trip_short_name"]) ?? ""
            let serviceID = normalized(row["service_id"]) ?? ""
            result[tripID] = TMBTrip(
                id: tripID,
                routeID: routeID,
                serviceID: serviceID,
                headsignKey: normalizedKey(headsign)
            )
        }
        return result
    }

    private func parseStopTimes(archive: Archive) -> [String: [TMBStopTime]] {
        guard let rows = try? parseOptionalRows(named: "stop_times.txt", from: archive), !rows.isEmpty else {
            return [:]
        }

        var buckets: [String: [TMBStopTime]] = [:]
        for row in rows {
            guard
                let tripID = normalized(row["trip_id"]),
                let stopID = normalized(row["stop_id"]),
                let arrival = normalized(row["arrival_time"]) ?? normalized(row["departure_time"])
            else {
                continue
            }

            let seconds = parseGTFSSeconds(from: arrival)
            buckets[stopID, default: []].append(TMBStopTime(tripID: tripID, arrivalSeconds: seconds))
        }
        return buckets
    }

    private func parseCalendar(archive: Archive) -> (
        calendars: [String: TMBServiceCalendar],
        exceptions: [Int: [String: TMBServiceExceptionType]]
    ) {
        var calendars: [String: TMBServiceCalendar] = [:]
        if let rows = try? parseOptionalRows(named: "calendar.txt", from: archive) {
            let weekdayColumns: [(column: String, weekday: Int)] = [
                ("sunday", 1),
                ("monday", 2),
                ("tuesday", 3),
                ("wednesday", 4),
                ("thursday", 5),
                ("friday", 6),
                ("saturday", 7),
            ]

            for row in rows {
                guard
                    let serviceID = normalized(row["service_id"]),
                    let startDateString = normalized(row["start_date"]),
                    let endDateString = normalized(row["end_date"]),
                    let startDayKey = parseGTFSDateKey(startDateString),
                    let endDayKey = parseGTFSDateKey(endDateString)
                else {
                    continue
                }

                var activeWeekdays: Set<Int> = []
                for (column, weekday) in weekdayColumns where row[column] == "1" {
                    activeWeekdays.insert(weekday)
                }

                calendars[serviceID] = TMBServiceCalendar(
                    serviceID: serviceID,
                    startDayKey: startDayKey,
                    endDayKey: endDayKey,
                    activeWeekdays: activeWeekdays
                )
            }
        }

        var exceptions: [Int: [String: TMBServiceExceptionType]] = [:]
        if let rows = try? parseOptionalRows(named: "calendar_dates.txt", from: archive) {
            for row in rows {
                guard
                    let serviceID = normalized(row["service_id"]),
                    let dateString = normalized(row["date"]),
                    let dayKey = parseGTFSDateKey(dateString),
                    let exceptionTypeString = normalized(row["exception_type"]),
                    let rawValue = Int(exceptionTypeString),
                    let exceptionType = TMBServiceExceptionType(rawValue: rawValue)
                else {
                    continue
                }

                exceptions[dayKey, default: [:]][serviceID] = exceptionType
            }
        }

        return (calendars, exceptions)
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

    private func parseOptionalRows(named name: String, from archive: Archive) throws -> [[String: String]] {
        let candidates = archive.filter { entry in
            entry.path == name || entry.path.hasSuffix("/\(name)")
        }

        guard candidates.first != nil else {
            return []
        }

        let text = try readEntry(named: name, from: archive)
        return try GTFSCSVParser.parse(text: text)
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

    private func parseGTFSSeconds(from time: String) -> Int {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else {
            return 0
        }
        return components[0] * 3_600 + components[1] * 60 + components[2]
    }

    private func parseGTFSDateKey(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 8 else {
            return nil
        }
        return Int(trimmed)
    }
}

public enum TMBStaticServiceError: Error, Equatable {
    case missingEntry(String)
    case invalidText(String)
}
