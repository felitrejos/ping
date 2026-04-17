import Foundation
import ZIPFoundation

public actor FGCStaticService: StaticServiceProviding {
    private struct GTFSStopTime: Sendable {
        let stopID: StopID
        let arrivalSeconds: Int
        let departureSeconds: Int
        let stopSequence: Int
    }

    private struct GTFSRoute: Sendable {
        let id: String
        let shortName: String
    }

    private struct GTFSTrip: Sendable {
        let id: String
        let routeID: String
        let serviceID: String
        let headsign: String
    }

    private struct GTFSServiceCalendar: Sendable {
        let serviceID: String
        let startDayKey: Int
        let endDayKey: Int
        let activeWeekdays: Set<Int>

        func isActive(dayKey: Int, weekday: Int) -> Bool {
            dayKey >= startDayKey && dayKey <= endDayKey && activeWeekdays.contains(weekday)
        }
    }

    private enum GTFSServiceExceptionType: Int, Sendable {
        case added = 1
        case removed = 2
    }

    private struct ParsedCache: Sendable {
        let stops: [StopID: Stop]
        let stopsSortedByName: [Stop]
        let stationStopsByID: [StopID: Stop]
        let stationSpatialIndex: FGCStopSpatialIndex
        let stopIDsByLine: [String: Set<StopID>]
        let linesByStopID: [StopID: Set<String>]
        let childStopIDs: [StopID: Set<StopID>]
        let parentStopID: [StopID: StopID]
        let routes: [String: GTFSRoute]
        let trips: [String: GTFSTrip]
        let stopTimesByTripID: [String: [GTFSStopTime]]
        let tripIDsByStopID: [StopID: [String]]
        let serviceCalendarsByID: [String: GTFSServiceCalendar]
        let serviceExceptionsByDayKey: [Int: [String: GTFSServiceExceptionType]]
        let stopsByLine: [String: [Stop]]
    }

    private struct GridCellKey: Hashable, Sendable {
        let latitudeIndex: Int
        let longitudeIndex: Int
    }

    private struct FGCStopSpatialIndex: Sendable {
        private let cellSize: Double
        private let stopsByCell: [GridCellKey: [Stop]]

        init(stops: [Stop], cellSize: Double = 0.01) {
            self.cellSize = cellSize

            var buckets: [GridCellKey: [Stop]] = [:]
            for stop in stops {
                guard let coordinate = stop.coordinate else {
                    continue
                }
                let key = GridCellKey(
                    latitudeIndex: Self.bucketIndex(for: coordinate.latitude, cellSize: cellSize),
                    longitudeIndex: Self.bucketIndex(for: coordinate.longitude, cellSize: cellSize)
                )
                buckets[key, default: []].append(stop)
            }
            stopsByCell = buckets
        }

        func stops(in region: TransitBoundingBox) -> [Stop] {
            let minLatitudeIndex = Self.bucketIndex(for: region.minLatitude, cellSize: cellSize)
            let maxLatitudeIndex = Self.bucketIndex(for: region.maxLatitude, cellSize: cellSize)
            let minLongitudeIndex = Self.bucketIndex(for: region.minLongitude, cellSize: cellSize)
            let maxLongitudeIndex = Self.bucketIndex(for: region.maxLongitude, cellSize: cellSize)

            var result: [Stop] = []
            for latitudeIndex in minLatitudeIndex ... maxLatitudeIndex {
                for longitudeIndex in minLongitudeIndex ... maxLongitudeIndex {
                    let key = GridCellKey(latitudeIndex: latitudeIndex, longitudeIndex: longitudeIndex)
                    guard let bucket = stopsByCell[key] else {
                        continue
                    }
                    result.append(contentsOf: bucket)
                }
            }

            return result.filter { stop in
                guard let coordinate = stop.coordinate else {
                    return false
                }
                return region.contains(coordinate)
            }
        }

        private static func bucketIndex(for coordinate: Double, cellSize: Double) -> Int {
            Int(floor(coordinate / cellSize))
        }
    }

    private var zipURL: URL
    private let calendar: Calendar
    private var cache: ParsedCache?

    public init(zipURL: URL, calendar: Calendar = .autoupdatingCurrent) {
        self.zipURL = zipURL
        self.calendar = calendar
    }

    /// Swap to a new ZIP URL (e.g. after downloading a fresh GTFS file) and clear the cache.
    public func updateZipURL(_ url: URL) {
        guard url != zipURL else { return }
        zipURL = url
        cache = nil
    }

    public func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture] {
        let cache = try loadCache()
        let originIDs = cache.childStopIDs[origin] ?? [origin]
        let destIDs = cache.childStopIDs[destination] ?? [destination]
        let serviceDays = candidateServiceDays(for: after)
        var departures: [TrainDeparture] = []
        var candidateTripIDs = Set<String>()

        for originID in originIDs {
            guard let tripIDs = cache.tripIDsByStopID[originID] else {
                continue
            }
            candidateTripIDs.formUnion(tripIDs)
        }

        for tripID in candidateTripIDs {
            guard
                let trip = cache.trips[tripID],
                let stopTimes = cache.stopTimesByTripID[tripID]
            else {
                continue
            }

            guard
                let originTime = stopTimes.first(where: { originIDs.contains($0.stopID) }),
                let destinationTime = stopTimes.first(where: { destIDs.contains($0.stopID) && $0.stopSequence > originTime.stopSequence }),
                let route = cache.routes[trip.routeID]
            else {
                continue
            }

            for serviceDay in serviceDays {
                guard tripRuns(on: serviceDay, serviceID: trip.serviceID, cache: cache) else {
                    continue
                }

                let departureDate = serviceDay.addingTimeInterval(TimeInterval(originTime.departureSeconds))
                guard departureDate >= after else {
                    continue
                }

                let arrivalDate = serviceDay.addingTimeInterval(TimeInterval(destinationTime.arrivalSeconds))
                departures.append(
                    TrainDeparture(
                        tripID: trip.id,
                        departureTime: departureDate,
                        arrivalTime: arrivalDate,
                        headsign: trip.headsign,
                        routeShortName: route.shortName
                    )
                )
            }
        }

        let sorted = departures.sorted { $0.departureTime < $1.departureTime }

        // Deduplicate by departure minute + route to avoid showing the same train multiple times
        var seen = Set<String>()
        return sorted.filter { departure in
            let key = "\(departure.routeShortName)-\(Int(departure.departureTime.timeIntervalSince1970 / 60))"
            return seen.insert(key).inserted
        }
    }

    public func departuresFrom(origin: StopID, after: Date, limit: Int) async throws -> [TrainDeparture] {
        let cache = try loadCache()
        let originIDs = cache.childStopIDs[origin] ?? [origin]
        let serviceDays = candidateServiceDays(for: after)
        var departures: [TrainDeparture] = []
        var candidateTripIDs = Set<String>()

        for originID in originIDs {
            guard let tripIDs = cache.tripIDsByStopID[originID] else {
                continue
            }
            candidateTripIDs.formUnion(tripIDs)
        }

        for tripID in candidateTripIDs {
            guard
                let trip = cache.trips[tripID],
                let stopTimes = cache.stopTimesByTripID[tripID],
                let originTime = stopTimes.first(where: { originIDs.contains($0.stopID) }),
                let terminalTime = stopTimes.last,
                let route = cache.routes[trip.routeID]
            else {
                continue
            }

            for serviceDay in serviceDays {
                guard tripRuns(on: serviceDay, serviceID: trip.serviceID, cache: cache) else {
                    continue
                }

                let departureDate = serviceDay.addingTimeInterval(TimeInterval(originTime.departureSeconds))
                guard departureDate >= after else {
                    continue
                }

                let arrivalDate = serviceDay.addingTimeInterval(TimeInterval(terminalTime.arrivalSeconds))
                departures.append(
                    TrainDeparture(
                        tripID: trip.id,
                        departureTime: departureDate,
                        arrivalTime: arrivalDate,
                        headsign: trip.headsign,
                        routeShortName: route.shortName
                    )
                )
            }
        }

        let sorted = departures.sorted { $0.departureTime < $1.departureTime }

        // Deduplicate by departure minute + route to avoid showing the same train multiple times.
        var seen = Set<String>()
        let deduped = sorted.filter { departure in
            let key = "\(departure.routeShortName)-\(Int(departure.departureTime.timeIntervalSince1970 / 60))"
            return seen.insert(key).inserted
        }

        return Array(deduped.prefix(max(0, limit)))
    }

    public func allStops() async throws -> [Stop] {
        try loadCache().stopsSortedByName
    }

    public func stops(in region: TransitBoundingBox) async throws -> [Stop] {
        let stops = try loadCache().stationSpatialIndex.stops(in: region)
        return stops.sorted { first, second in
            let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return first.id < second.id
        }
    }

    /// Returns all stations considered compatible with `stopID` using a non-directional line-based match.
    /// If a station belongs to multiple lines, compatibility is the union of stations for those lines.
    public func compatibleStopIDs(for stopID: StopID) async throws -> Set<StopID> {
        let cache = try loadCache()
        guard !stopID.isEmpty else {
            return []
        }

        guard let lineNames = cache.linesByStopID[stopID], !lineNames.isEmpty else {
            return Set([stopID])
        }

        var compatible = Set<StopID>([stopID])
        for line in lineNames {
            compatible.formUnion(cache.stopIDsByLine[line] ?? [])
        }
        return compatible
    }

    public func stopsForLine(_ lineName: String) async throws -> [Stop] {
        try loadCache().stopsByLine[lineName] ?? []
    }

    public func linesForStop(_ stopID: StopID) async throws -> [String] {
        guard let lines = try loadCache().linesByStopID[stopID] else {
            return []
        }
        // Sort so the dots render in a deterministic order across app launches. Lexicographic
        // ordering matches how FGC labels lines (R1, R2, …, S1, S2, …).
        return lines.sorted()
    }

    public func searchStops(matching query: String) async throws -> [Stop] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return try loadCache().stopsSortedByName
        }

        return try loadCache().stopsSortedByName.filter { stop in
            normalize(stop.name).localizedStandardContains(normalizedQuery)
        }
    }

    public func lineForRoute(origin: StopID, destination: StopID) async throws -> String? {
        let cache = try loadCache()
        for (line, stops) in cache.stopsByLine {
            let ids = Set(stops.map(\.id))
            if ids.contains(origin) && ids.contains(destination) {
                return line
            }
        }
        return nil
    }

    public func routeStops(origin: StopID, destination: StopID) async throws -> [Stop] {
        let cache = try loadCache()
        let originIDs = cache.childStopIDs[origin] ?? [origin]
        let destinationIDs = cache.childStopIDs[destination] ?? [destination]

        for tripID in cache.stopTimesByTripID.keys.sorted() {
            guard let stopTimes = cache.stopTimesByTripID[tripID] else {
                continue
            }

            guard
                let originIndex = stopTimes.firstIndex(where: { originIDs.contains($0.stopID) }),
                let destinationIndex = stopTimes[originIndex...].firstIndex(where: { destinationIDs.contains($0.stopID) }),
                destinationIndex > originIndex
            else {
                continue
            }

            var seen = Set<StopID>()
            return stopTimes[originIndex...destinationIndex].compactMap { stopTime in
                let stationID = cache.parentStopID[stopTime.stopID] ?? stopTime.stopID
                guard seen.insert(stationID).inserted else {
                    return nil
                }

                return cache.stationStopsByID[stationID] ?? cache.stops[stationID]
            }
        }

        return []
    }
}

// MARK: - Parsing
extension FGCStaticService {
    private func loadCache() throws -> ParsedCache {
        if let cache {
            return cache
        }

        let archive = try Archive(url: zipURL, accessMode: .read)
        let stopsRows = try GTFSCSVParser.parse(text: try readEntry(named: "stops.txt", from: archive))
        let routesRows = try GTFSCSVParser.parse(text: try readEntry(named: "routes.txt", from: archive))
        let tripsRows = try GTFSCSVParser.parse(text: try readEntry(named: "trips.txt", from: archive))
        let stopTimesRows = try GTFSCSVParser.parse(text: try readEntry(named: "stop_times.txt", from: archive))
        let calendarRows = try parseOptionalRows(named: "calendar.txt", from: archive)
        let calendarDateRows = try parseOptionalRows(named: "calendar_dates.txt", from: archive)

        let stopPairs: [(String, Stop)] = stopsRows.compactMap { row in
            guard let stopID = row["stop_id"], let stopName = row["stop_name"] else {
                return nil
            }
            let lat = row["stop_lat"].flatMap(Double.init)
            let lon = row["stop_lon"].flatMap(Double.init)
            return (stopID, Stop(id: stopID, name: stopName, latitude: lat, longitude: lon))
        }
        let stops = Dictionary(uniqueKeysWithValues: stopPairs)

        // Build parent → children mapping so departuresBetween can match platform-level IDs
        var childStopIDs: [StopID: Set<StopID>] = [:]
        for row in stopsRows {
            guard
                let stopID = row["stop_id"],
                let parentStation = row["parent_station"],
                !parentStation.isEmpty
            else {
                continue
            }
            childStopIDs[parentStation, default: []].insert(stopID)
        }

        // Only expose parent stations (location_type=1) or stops without a parent for the picker
        let stationStops: [Stop] = stopsRows.compactMap { row in
            guard let stopID = row["stop_id"], let stopName = row["stop_name"] else {
                return nil
            }
            let locationType = row["location_type"] ?? "0"
            let parentStation = row["parent_station"] ?? ""
            // Include parent stations (type 1) and standalone stops (type 0 with no parent)
            if locationType == "1" || parentStation.isEmpty {
                let lat = row["stop_lat"].flatMap(Double.init)
                let lon = row["stop_lon"].flatMap(Double.init)
                return Stop(id: stopID, name: stopName, latitude: lat, longitude: lon)
            }
            return nil
        }.sorted { $0.name < $1.name }

        let routePairs: [(String, GTFSRoute)] = routesRows.compactMap { row in
            guard let routeID = row["route_id"] else {
                return nil
            }
            return (routeID, GTFSRoute(id: routeID, shortName: row["route_short_name"] ?? routeID))
        }
        let routes = Dictionary(uniqueKeysWithValues: routePairs)

        let tripPairs: [(String, GTFSTrip)] = tripsRows.compactMap { row in
            guard
                let tripID = row["trip_id"],
                let routeID = row["route_id"],
                let serviceID = row["service_id"]
            else {
                return nil
            }
            return (
                tripID,
                GTFSTrip(
                    id: tripID,
                    routeID: routeID,
                    serviceID: serviceID,
                    headsign: row["trip_headsign"] ?? row["trip_short_name"] ?? routeID
                )
            )
        }
        let trips = Dictionary(uniqueKeysWithValues: tripPairs)

        let serviceCalendarsByID: [String: GTFSServiceCalendar] = Dictionary(
            uniqueKeysWithValues: calendarRows.compactMap { row in
                guard
                    let serviceID = row["service_id"],
                    let startDateString = row["start_date"],
                    let endDateString = row["end_date"],
                    let startDayKey = parseGTFSDateKey(startDateString),
                    let endDayKey = parseGTFSDateKey(endDateString)
                else {
                    return nil
                }

                var activeWeekdays = Set<Int>()
                let weekdayColumns: [(column: String, weekday: Int)] = [
                    ("sunday", 1),
                    ("monday", 2),
                    ("tuesday", 3),
                    ("wednesday", 4),
                    ("thursday", 5),
                    ("friday", 6),
                    ("saturday", 7),
                ]

                for (column, weekday) in weekdayColumns {
                    if row[column] == "1" {
                        activeWeekdays.insert(weekday)
                    }
                }

                return (
                    serviceID,
                    GTFSServiceCalendar(
                        serviceID: serviceID,
                        startDayKey: startDayKey,
                        endDayKey: endDayKey,
                        activeWeekdays: activeWeekdays
                    )
                )
            }
        )

        var serviceExceptionsByDayKey: [Int: [String: GTFSServiceExceptionType]] = [:]
        for row in calendarDateRows {
            guard
                let serviceID = row["service_id"],
                let dateString = row["date"],
                let dayKey = parseGTFSDateKey(dateString),
                let exceptionTypeString = row["exception_type"],
                let exceptionTypeRawValue = Int(exceptionTypeString),
                let exceptionType = GTFSServiceExceptionType(rawValue: exceptionTypeRawValue)
            else {
                continue
            }

            serviceExceptionsByDayKey[dayKey, default: [:]][serviceID] = exceptionType
        }

        let stopTimePairs: [(String, GTFSStopTime)] = stopTimesRows.compactMap { row in
            guard
                let tripID = row["trip_id"],
                let stopID = row["stop_id"],
                let arrival = row["arrival_time"],
                let departure = row["departure_time"],
                let stopSequenceString = row["stop_sequence"],
                let stopSequence = Int(stopSequenceString)
            else {
                return nil
            }

            return (
                tripID,
                GTFSStopTime(
                    stopID: stopID,
                    arrivalSeconds: parseGTFSSeconds(from: arrival),
                    departureSeconds: parseGTFSSeconds(from: departure),
                    stopSequence: stopSequence
                )
            )
        }
        let stopTimes = Dictionary(grouping: stopTimePairs, by: { $0.0 })
            .mapValues { $0.map(\.1).sorted { $0.stopSequence < $1.stopSequence } }
        var tripIDsByStopID: [StopID: Set<String>] = [:]
        for (tripID, tripStopTimes) in stopTimes {
            for stopTime in tripStopTimes {
                tripIDsByStopID[stopTime.stopID, default: []].insert(tripID)
            }
        }

        // Build parent lookup (child → parent)
        var parentStopID: [StopID: StopID] = [:]
        for (parent, children) in childStopIDs {
            for child in children {
                parentStopID[child] = parent
            }
        }

        // Build line → parent station IDs mapping
        var stopIDsByLine: [String: Set<StopID>] = [:]
        for (tripID, trip) in trips {
            guard let route = routes[trip.routeID],
                  let tripStopTimes = stopTimes[tripID] else { continue }
            for st in tripStopTimes {
                let parentID = parentStopID[st.stopID] ?? st.stopID
                stopIDsByLine[route.shortName, default: []].insert(parentID)
            }
        }

        var linesByStopID: [StopID: Set<String>] = [:]
        for (line, stopIDs) in stopIDsByLine {
            for stopID in stopIDs {
                linesByStopID[stopID, default: []].insert(line)
            }
        }

        let stationStopsByID = Dictionary(uniqueKeysWithValues: stationStops.map { ($0.id, $0) })
        var stopsByLine: [String: [Stop]] = [:]
        for (line, ids) in stopIDsByLine {
            stopsByLine[line] = ids.compactMap { stationStopsByID[$0] }.sorted { $0.name < $1.name }
        }

        let parsed = ParsedCache(
            stops: stops,
            stopsSortedByName: stationStops,
            stationStopsByID: stationStopsByID,
            stationSpatialIndex: FGCStopSpatialIndex(stops: stationStops),
            stopIDsByLine: stopIDsByLine,
            linesByStopID: linesByStopID,
            childStopIDs: childStopIDs,
            parentStopID: parentStopID,
            routes: routes,
            trips: trips,
            stopTimesByTripID: stopTimes,
            tripIDsByStopID: tripIDsByStopID.mapValues(Array.init),
            serviceCalendarsByID: serviceCalendarsByID,
            serviceExceptionsByDayKey: serviceExceptionsByDayKey,
            stopsByLine: stopsByLine
        )
        cache = parsed
        return parsed
    }

    private func readEntry(named name: String, from archive: Archive) throws -> String {
        guard let entry = archive[name] else {
            throw StaticServiceError.missingEntry(name)
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw StaticServiceError.invalidText(name)
        }
        return text
    }

    private func parseOptionalRows(named name: String, from archive: Archive) throws -> [[String: String]] {
        guard archive[name] != nil else {
            return []
        }
        let text = try readEntry(named: name, from: archive)
        return try GTFSCSVParser.parse(text: text)
    }

    private func candidateServiceDays(for date: Date) -> [Date] {
        let startOfToday = calendar.startOfDay(for: date)
        guard
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfToday),
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else {
            return [startOfToday]
        }
        return [previousDay, startOfToday, nextDay]
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

    private func tripRuns(on serviceDay: Date, serviceID: String, cache: ParsedCache) -> Bool {
        guard
            let dayKey = dayKey(for: serviceDay)
        else {
            return false
        }

        if let exception = cache.serviceExceptionsByDayKey[dayKey]?[serviceID] {
            switch exception {
            case .added:
                return true
            case .removed:
                return false
            }
        }

        guard let serviceCalendar = cache.serviceCalendarsByID[serviceID] else {
            return false
        }

        let weekday = calendar.component(.weekday, from: serviceDay)
        return serviceCalendar.isActive(dayKey: dayKey, weekday: weekday)
    }

    private func normalize(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum StaticServiceError: Error, Equatable {
    case missingEntry(String)
    case invalidText(String)
}
