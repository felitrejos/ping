#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct PingActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let minutesUntilDeparture: Int
        public let walkMinutes: Int
        public let rideMinutes: Int
        public let departureTimestamp: TimeInterval
        public let arrivalTimestamp: TimeInterval

        public init(
            minutesUntilDeparture: Int,
            walkMinutes: Int,
            rideMinutes: Int,
            departureTime: Date,
            arrivalTime: Date
        ) {
            self.minutesUntilDeparture = minutesUntilDeparture
            self.walkMinutes = walkMinutes
            self.rideMinutes = rideMinutes
            self.departureTimestamp = departureTime.timeIntervalSince1970
            self.arrivalTimestamp = arrivalTime.timeIntervalSince1970
        }

        public var leaveInMinutes: Int {
            max(0, minutesUntilDeparture - walkMinutes)
        }

        public var departureTime: Date {
            Date(timeIntervalSince1970: departureTimestamp)
        }

        public var arrivalTime: Date {
            Date(timeIntervalSince1970: arrivalTimestamp)
        }
    }

    public let destinationName: String
    public let lineName: String

    public init(destinationName: String, lineName: String) {
        self.destinationName = destinationName
        self.lineName = lineName
    }
}
#endif
