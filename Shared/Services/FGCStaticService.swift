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
        let routes: [String: GTFSRoute]
        let trips: [String: GTFSTrip]
        let stopTimesByTripID: [String: [GTFSStopTime]]
    }

    private let zipURL: URL
    private let calendar: Calendar
    private var cache: ParsedCache?

    public init(zipURL: URL, calendar: Calendar = .autoupdatingCurrent) {
        self.zipURL = zipURL
        self.calendar = calendar
    }

    public func departuresBetween(origin: StopID, destination: StopID, after: Date) async throws -> [TrainDeparture] {
        let cache = try loadCache()
        let serviceDays = candidateServiceDays(for: after)
        var departures: [TrainDeparture] = []

        for trip in cache.trips.values {
            guard let stopTimes = cache.stopTimesByTripID[trip.id] else {
                continue
            }

            guard
                let originTime = stopTimes.first(where: { $0.stopID == origin }),
                let destinationTime = stopTimes.first(where: { $0.stopID == destination && $0.stopSequence > originTime.stopSequence }),
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

        return departures.sorted { $0.departureTime < $1.departureTime }
    }

    public func allStops() async throws -> [Stop] {
        try loadCache().stopsSortedByName
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
            return (stopID, Stop(id: stopID, name: stopName))
        }
        let stops = Dictionary(uniqueKeysWithValues: stopPairs)

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

        let parsed = ParsedCache(
            stops: stops,
            stopsSortedByName: stops.values.sorted { $0.name < $1.name },
            routes: routes,
            trips: trips,
            stopTimesByTripID: stopTimes
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
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return [startOfToday]
        }
        return [previousDay, startOfToday]
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
