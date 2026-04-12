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
        let headsign: String
    }

    private struct ParsedCache: Sendable {
        let stops: [StopID: Stop]
        let stopsSortedByName: [Stop]
        let childStopIDs: [StopID: Set<StopID>]
        let parentStopID: [StopID: StopID]
        let routes: [String: GTFSRoute]
        let trips: [String: GTFSTrip]
        let stopTimesByTripID: [String: [GTFSStopTime]]
        let stationStopsByID: [StopID: Stop]
        let lineNames: [String]
        let stopsByLine: [String: [Stop]]
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

        for trip in cache.trips.values {
            guard let stopTimes = cache.stopTimesByTripID[trip.id] else {
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

    public func allStops() async throws -> [Stop] {
        try loadCache().stopsSortedByName
    }

    public func availableLines() async throws -> [String] {
        try loadCache().lineNames
    }

    public func stopsForLine(_ lineName: String) async throws -> [Stop] {
        try loadCache().stopsByLine[lineName] ?? []
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
            guard let tripID = row["trip_id"], let routeID = row["route_id"] else {
                return nil
            }
            return (
                tripID,
                GTFSTrip(
                    id: tripID,
                    routeID: routeID,
                    headsign: row["trip_headsign"] ?? row["trip_short_name"] ?? routeID
                )
            )
        }
        let trips = Dictionary(uniqueKeysWithValues: tripPairs)

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

        let stationStopsByID = Dictionary(uniqueKeysWithValues: stationStops.map { ($0.id, $0) })
        var stopsByLine: [String: [Stop]] = [:]
        for (line, ids) in stopIDsByLine {
            stopsByLine[line] = ids.compactMap { stationStopsByID[$0] }.sorted { $0.name < $1.name }
        }
        let lineNames = stopIDsByLine.keys.sorted()

        let parsed = ParsedCache(
            stops: stops,
            stopsSortedByName: stationStops,
            childStopIDs: childStopIDs,
            parentStopID: parentStopID,
            routes: routes,
            trips: trips,
            stopTimesByTripID: stopTimes,
            stationStopsByID: stationStopsByID,
            lineNames: lineNames,
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
