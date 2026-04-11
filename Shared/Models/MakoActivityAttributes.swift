#if canImport(ActivityKit) && os(iOS)
import ActivityKit

public struct MakoActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let minutesUntilDeparture: Int
        public let isDelayed: Bool
        public let delayMinutes: Int

        public init(minutesUntilDeparture: Int, isDelayed: Bool, delayMinutes: Int) {
            self.minutesUntilDeparture = minutesUntilDeparture
            self.isDelayed = isDelayed
            self.delayMinutes = delayMinutes
        }
    }

    public let eventTitle: String
    public let trainLabel: String

    public init(eventTitle: String, trainLabel: String) {
        self.eventTitle = eventTitle
        self.trainLabel = trainLabel
    }
}
#endif
