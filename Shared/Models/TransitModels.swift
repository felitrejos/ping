import Foundation

public typealias StopID = String

public struct TransitCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct TransitBoundingBox: Equatable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double
    ) {
        self.minLatitude = min(minLatitude, maxLatitude)
        self.maxLatitude = max(minLatitude, maxLatitude)
        self.minLongitude = min(minLongitude, maxLongitude)
        self.maxLongitude = max(minLongitude, maxLongitude)
    }

    public func contains(_ coordinate: TransitCoordinate) -> Bool {
        coordinate.latitude >= minLatitude
            && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude
            && coordinate.longitude <= maxLongitude
    }
}

public struct Stop: Codable, Equatable, Identifiable, Sendable {
    public let id: StopID
    public let name: String
    public let latitude: Double?
    public let longitude: Double?

    public init(id: StopID, name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: TransitCoordinate? {
        guard let latitude, let longitude else {
            return nil
        }

        return TransitCoordinate(latitude: latitude, longitude: longitude)
    }
}

public struct TrainDeparture: Codable, Equatable, Identifiable, Sendable {
    public let tripID: String
    public let departureTime: Date
    public let arrivalTime: Date
    public let headsign: String
    public let routeShortName: String

    public var id: String {
        "\(tripID)-\(departureTime.timeIntervalSince1970)"
    }

    public init(
        tripID: String,
        departureTime: Date,
        arrivalTime: Date,
        headsign: String,
        routeShortName: String
    ) {
        self.tripID = tripID
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.headsign = headsign
        self.routeShortName = routeShortName
    }
}

public struct CommuteEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let location: String?
    public let resolvedStation: StopID?
    public let stationCandidateIDs: [StopID]

    public init(
        id: String,
        title: String,
        startDate: Date,
        location: String?,
        resolvedStation: StopID?,
        stationCandidateIDs: [StopID] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
        self.resolvedStation = resolvedStation
        self.stationCandidateIDs = stationCandidateIDs
    }
}

public struct LiveDeparture: Codable, Equatable, Identifiable, Sendable {
    public let scheduledTime: Date
    public let arrivalTime: Date
    public let delaySeconds: Int
    public let trainLabel: String
    public let minutesUntilDeparture: Int
    public let tripID: String
    public let destinationStopID: StopID

    public var effectiveDepartureTime: Date {
        scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    public var effectiveArrivalTime: Date {
        arrivalTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    public var isDelayed: Bool {
        delaySeconds > 0
    }

    public var delayMinutes: Int {
        max(0, delaySeconds / 60)
    }

    public var statusText: String {
        isDelayed ? "+\(delayMinutes) min" : "On time"
    }

    public var id: String {
        "\(tripID)-\(scheduledTime.timeIntervalSince1970)"
    }

    public init(
        scheduledTime: Date,
        arrivalTime: Date,
        delaySeconds: Int,
        trainLabel: String,
        minutesUntilDeparture: Int,
        tripID: String,
        destinationStopID: StopID
    ) {
        self.scheduledTime = scheduledTime
        self.arrivalTime = arrivalTime
        self.delaySeconds = delaySeconds
        self.trainLabel = trainLabel
        self.minutesUntilDeparture = minutesUntilDeparture
        self.tripID = tripID
        self.destinationStopID = destinationStopID
    }
}

public struct StationDeparture: Codable, Equatable, Identifiable, Sendable {
    public let tripID: String
    public let routeShortName: String
    public let headsign: String
    public let scheduledDepartureTime: Date
    public let delaySeconds: Int
    public let minutesUntilDeparture: Int

    public var effectiveDepartureTime: Date {
        scheduledDepartureTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    public var id: String {
        "\(tripID)-\(scheduledDepartureTime.timeIntervalSince1970)"
    }

    public init(
        tripID: String,
        routeShortName: String,
        headsign: String,
        scheduledDepartureTime: Date,
        delaySeconds: Int,
        minutesUntilDeparture: Int
    ) {
        self.tripID = tripID
        self.routeShortName = routeShortName
        self.headsign = headsign
        self.scheduledDepartureTime = scheduledDepartureTime
        self.delaySeconds = delaySeconds
        self.minutesUntilDeparture = minutesUntilDeparture
    }
}

public struct CommutePlan: Codable, Equatable, Identifiable, Sendable {
    public let calendarEvent: CommuteEvent
    public let originStationID: StopID
    public let destinationStationID: StopID
    public let recommendedDeparture: Date
    public let trainOptions: [LiveDeparture]

    public var id: String {
        calendarEvent.id
    }

    public init(
        calendarEvent: CommuteEvent,
        originStationID: StopID,
        destinationStationID: StopID,
        recommendedDeparture: Date,
        trainOptions: [LiveDeparture]
    ) {
        self.calendarEvent = calendarEvent
        self.originStationID = originStationID
        self.destinationStationID = destinationStationID
        self.recommendedDeparture = recommendedDeparture
        self.trainOptions = trainOptions
    }
}

/// High-level state machine for the commute hero and Live Activity.
///
/// * `.planning` — no specific trip is locked; the hero auto-rolls to the next catchable train.
/// * `.tracking` — the user tapped *Follow trip*; we lock to a specific `tripID` and render
///   tracking-focused metrics (ETA to station, train departs in, buffer +/-).
/// * `.likelyMissed` — the tracked trip hasn't departed yet, but the buffer turned negative
///   enough that the user is almost certainly going to miss it if they don't act now.
/// * `.missed` — the tracked trip's effective departure time has passed.
public enum TrackingPhase: String, Codable, Equatable, Sendable {
    case planning
    case tracking
    case likelyMissed
    case missed
}

public enum ServiceAlertSeverity: String, Codable, Equatable, Sendable {
    case info
    case minor
    case major
    case closure
}

public struct ServiceAlert: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let details: String?
    public let affectedLines: [String]
    public let severity: ServiceAlertSeverity
    public let startDate: Date?
    public let endDate: Date?

    public init(
        id: String,
        title: String,
        details: String?,
        affectedLines: [String],
        severity: ServiceAlertSeverity,
        startDate: Date?,
        endDate: Date?
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.affectedLines = affectedLines
        self.severity = severity
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct CalendarEventRecord: Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let location: String?
    public let coordinate: TransitCoordinate?

    public init(
        id: String,
        title: String,
        startDate: Date,
        location: String?,
        coordinate: TransitCoordinate? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
        self.coordinate = coordinate
    }
}

public enum CalendarAuthorizationState: String, Codable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case fullAccess
    case writeOnly

    public var isAuthorized: Bool {
        self == .authorized || self == .fullAccess || self == .writeOnly
    }
}

public enum UserSettings {
    public enum Keys {
        public static let homeStationID = "ping.userHomeStation"
        public static let destinationStationID = "ping.destinationStation"
        public static let walkingMinutes = "ping.walkingMinutes"
        public static let bufferMinutes = "ping.bufferMinutes"
        public static let selectedLine = "ping.selectedLine"
        public static let menuBarSleepMode = "ping.menuBarSleepMode"
        public static let favoriteStationIDs = "ping.favoriteStationIDs"
        public static let didMigrateLegacyDefaultRoute = "ping.didMigrateLegacyDefaultRoute"
        public static let tmbEnabled = "ping.tmbEnabled"
        public static let fgcEnabled = "ping.fgcEnabled"
    }

    public static let defaultWalkingMinutes = 8
    public static let defaultBufferMinutes = 3
    private static let legacyDefaultHomeStationID = "VO"
    private static let legacyDefaultDestinationStationID = "SR"

    public static func migrateLegacyDefaultRouteIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Keys.didMigrateLegacyDefaultRoute) else {
            return
        }

        if defaults.string(forKey: Keys.homeStationID) == legacyDefaultHomeStationID {
            defaults.removeObject(forKey: Keys.homeStationID)
        }

        if defaults.string(forKey: Keys.destinationStationID) == legacyDefaultDestinationStationID {
            defaults.removeObject(forKey: Keys.destinationStationID)
        }

        defaults.set(true, forKey: Keys.didMigrateLegacyDefaultRoute)
    }

    public static func homeStationID(defaults: UserDefaults = .standard) -> StopID? {
        guard let value = defaults.string(forKey: Keys.homeStationID) else {
            return nil
        }

        return isConfiguredStopID(value) ? value : nil
    }

    public static func setHomeStationID(_ stopID: StopID?, defaults: UserDefaults = .standard) {
        if let stopID {
            defaults.set(stopID, forKey: Keys.homeStationID)
        } else {
            defaults.removeObject(forKey: Keys.homeStationID)
        }
    }

    public static func destinationStationID(defaults: UserDefaults = .standard) -> StopID? {
        guard let value = defaults.string(forKey: Keys.destinationStationID) else {
            return nil
        }

        return isConfiguredStopID(value) ? value : nil
    }

    public static func setDestinationStationID(_ stopID: StopID?, defaults: UserDefaults = .standard) {
        if let stopID {
            defaults.set(stopID, forKey: Keys.destinationStationID)
        } else {
            defaults.removeObject(forKey: Keys.destinationStationID)
        }
    }

    public static func walkingMinutes(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: Keys.walkingMinutes) as? Int
        return value ?? defaultWalkingMinutes
    }

    public static func setWalkingMinutes(_ minutes: Int, defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: Keys.walkingMinutes)
    }

    public static func bufferMinutes(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: Keys.bufferMinutes) as? Int
        return value ?? defaultBufferMinutes
    }

    public static func setBufferMinutes(_ minutes: Int, defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: Keys.bufferMinutes)
    }

    public static let defaultSelectedLine = "S2"
    public static let defaultTMBEnabled = true
    public static let defaultFGCEnabled = true

    public static func selectedLine(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: Keys.selectedLine) ?? defaultSelectedLine
    }

    public static func setSelectedLine(_ line: String, defaults: UserDefaults = .standard) {
        defaults.set(line, forKey: Keys.selectedLine)
    }

    public static func tmbEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: Keys.tmbEnabled) == nil {
            return defaultTMBEnabled
        }
        return defaults.bool(forKey: Keys.tmbEnabled)
    }

    public static func setTMBEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.tmbEnabled)
    }

    public static func fgcEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: Keys.fgcEnabled) == nil {
            return defaultFGCEnabled
        }
        return defaults.bool(forKey: Keys.fgcEnabled)
    }

    public static func setFGCEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.fgcEnabled)
    }

    public static func favoriteStationIDs(defaults: UserDefaults = .standard) -> [StopID] {
        guard let data = defaults.data(forKey: Keys.favoriteStationIDs) else {
            return []
        }

        let decoded = (try? JSONDecoder().decode([StopID].self, from: data)) ?? []
        var seen: Set<StopID> = []
        return decoded.filter { stopID in
            guard isConfiguredStopID(stopID) else {
                return false
            }

            if seen.contains(stopID) {
                return false
            }

            seen.insert(stopID)
            return true
        }
    }

    public static func setFavoriteStationIDs(_ stopIDs: [StopID], defaults: UserDefaults = .standard) {
        let cleaned = stopIDs
            .filter { isConfiguredStopID($0) }
            .reduce(into: [StopID]()) { result, stopID in
                if !result.contains(stopID) {
                    result.append(stopID)
                }
            }

        if cleaned.isEmpty {
            defaults.removeObject(forKey: Keys.favoriteStationIDs)
            return
        }

        if let encoded = try? JSONEncoder().encode(cleaned) {
            defaults.set(encoded, forKey: Keys.favoriteStationIDs)
        }
    }

    public static func gtfsLastFetched(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "ping.gtfsLastFetched") as? Date
    }

    public static func setGTFSLastFetched(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: "ping.gtfsLastFetched")
    }

    public static func tmbGTFSLastFetched(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "ping.tmbGTFSLastFetched") as? Date
    }

    public static func setTMBGTFSLastFetched(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: "ping.tmbGTFSLastFetched")
    }

    public static func isConfiguredStopID(_ stopID: StopID?) -> Bool {
        guard let stopID else {
            return false
        }

        return !stopID.isEmpty
    }
}
