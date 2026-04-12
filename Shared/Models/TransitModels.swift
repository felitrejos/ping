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
    public let stationCandidatesDebug: [String]

    public init(
        id: String,
        title: String,
        startDate: Date,
        location: String?,
        resolvedStation: StopID?,
        stationCandidateIDs: [StopID] = [],
        stationCandidatesDebug: [String] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
        self.resolvedStation = resolvedStation
        self.stationCandidateIDs = stationCandidateIDs
        self.stationCandidatesDebug = stationCandidatesDebug
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
        public static let autoSelectClosestOrigin = "ping.autoSelectClosestOrigin"
        public static let didMigrateLegacyDefaultRoute = "ping.didMigrateLegacyDefaultRoute"
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

    public static func selectedLine(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: Keys.selectedLine) ?? defaultSelectedLine
    }

    public static func setSelectedLine(_ line: String, defaults: UserDefaults = .standard) {
        defaults.set(line, forKey: Keys.selectedLine)
    }

    public static func autoSelectClosestOrigin(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.autoSelectClosestOrigin)
    }

    public static func setAutoSelectClosestOrigin(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.autoSelectClosestOrigin)
    }

    public static func gtfsLastFetched(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "ping.gtfsLastFetched") as? Date
    }

    public static func setGTFSLastFetched(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: "ping.gtfsLastFetched")
    }

    public static func isConfiguredStopID(_ stopID: StopID?) -> Bool {
        guard let stopID else {
            return false
        }

        return !stopID.isEmpty
    }
}
