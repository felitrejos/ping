import Foundation

public typealias StopID = String

public struct Stop: Codable, Equatable, Identifiable, Sendable {
    public let id: StopID
    public let name: String

    public init(id: StopID, name: String) {
        self.id = id
        self.name = name
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

    public init(
        id: String,
        title: String,
        startDate: Date,
        location: String?,
        resolvedStation: StopID?
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
        self.resolvedStation = resolvedStation
    }
}

public struct LiveDeparture: Codable, Equatable, Identifiable, Sendable {
    public let scheduledTime: Date
    public let delaySeconds: Int
    public let trainLabel: String
    public let minutesUntilDeparture: Int
    public let tripID: String
    public let destinationStopID: StopID

    public var effectiveDepartureTime: Date {
        scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
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
        delaySeconds: Int,
        trainLabel: String,
        minutesUntilDeparture: Int,
        tripID: String,
        destinationStopID: StopID
    ) {
        self.scheduledTime = scheduledTime
        self.delaySeconds = delaySeconds
        self.trainLabel = trainLabel
        self.minutesUntilDeparture = minutesUntilDeparture
        self.tripID = tripID
        self.destinationStopID = destinationStopID
    }
}

public struct CommutePlan: Codable, Equatable, Identifiable, Sendable {
    public let calendarEvent: CommuteEvent
    public let recommendedDeparture: Date
    public let trainOptions: [LiveDeparture]

    public var id: String {
        calendarEvent.id
    }

    public init(
        calendarEvent: CommuteEvent,
        recommendedDeparture: Date,
        trainOptions: [LiveDeparture]
    ) {
        self.calendarEvent = calendarEvent
        self.recommendedDeparture = recommendedDeparture
        self.trainOptions = trainOptions
    }
}

public struct CalendarEventRecord: Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let location: String?

    public init(id: String, title: String, startDate: Date, location: String?) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
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
    public static let defaultHomeStationID = "VO"
    public static let defaultDestinationStationID = "SR"

    public enum Keys {
        public static let homeStationID = "mako.userHomeStation"
        public static let destinationStationID = "mako.destinationStation"
        public static let walkingMinutes = "mako.walkingMinutes"
        public static let bufferMinutes = "mako.bufferMinutes"
        public static let selectedLine = "mako.selectedLine"
    }

    public static let defaultWalkingMinutes = 8
    public static let defaultBufferMinutes = 3

    public static func homeStationID(defaults: UserDefaults = .standard) -> StopID? {
        let value = defaults.string(forKey: Keys.homeStationID) ?? defaultHomeStationID
        return isConfiguredStopID(value) ? value : nil
    }

    public static func setHomeStationID(_ stopID: StopID?, defaults: UserDefaults = .standard) {
        defaults.set(stopID, forKey: Keys.homeStationID)
    }

    public static func destinationStationID(defaults: UserDefaults = .standard) -> StopID? {
        let value = defaults.string(forKey: Keys.destinationStationID) ?? defaultDestinationStationID
        return isConfiguredStopID(value) ? value : nil
    }

    public static func setDestinationStationID(_ stopID: StopID?, defaults: UserDefaults = .standard) {
        defaults.set(stopID, forKey: Keys.destinationStationID)
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

    public static func isConfiguredStopID(_ stopID: StopID?) -> Bool {
        guard let stopID else {
            return false
        }

        return !stopID.isEmpty
    }
}
