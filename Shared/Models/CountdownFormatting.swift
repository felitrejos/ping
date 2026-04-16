import Foundation

public struct HeroCountdownParts: Sendable {
    public let leadingValue: String
    public let leadingUnit: String
    public let trailingValue: String?
    public let trailingUnit: String?
    public let isLongForm: Bool

    public init(
        leadingValue: String,
        leadingUnit: String,
        trailingValue: String?,
        trailingUnit: String?,
        isLongForm: Bool
    ) {
        self.leadingValue = leadingValue
        self.leadingUnit = leadingUnit
        self.trailingValue = trailingValue
        self.trailingUnit = trailingUnit
        self.isLongForm = isLongForm
    }
}

public enum CountdownFormatting {
    public static func remainingSeconds(until targetDate: Date, now: Date = .now) -> Int {
        max(0, Int(targetDate.timeIntervalSince(now)))
    }

    public static func heroParts(remainingSeconds: Int) -> HeroCountdownParts {
        let normalized = max(0, remainingSeconds)
        let hours = normalized / 3600
        let minutes = (normalized % 3600) / 60

        if normalized >= 3600 {
            return HeroCountdownParts(
                leadingValue: "\(hours)",
                leadingUnit: "h",
                trailingValue: "\(minutes)",
                trailingUnit: "min",
                isLongForm: true
            )
        }

        return HeroCountdownParts(
            leadingValue: "\(minutes)",
            leadingUnit: "min",
            trailingValue: nil,
            trailingUnit: nil,
            isLongForm: false
        )
    }

    public static func boardText(remainingSeconds: Int) -> String {
        let normalized = max(0, remainingSeconds)
        let hours = normalized / 3600
        let minutes = (normalized % 3600) / 60
        let seconds = normalized % 60

        if normalized >= 3600 {
            return "\(hours)h \(minutes)min"
        }

        return "\(minutes)m \(seconds)s"
    }

    /// Compact countdown for minute-resolution values (e.g. next-arrival labels on the map).
    /// Falls back to hours when the countdown crosses 60 minutes so labels don't drift to
    /// "90 min" / "300 min" territory.
    public static func compactMinutesText(minutes: Int) -> String {
        let normalized = max(0, minutes)
        if normalized >= 60 {
            let hours = normalized / 60
            let remainder = normalized % 60
            if remainder == 0 {
                return "\(hours) h"
            }
            return "\(hours) h \(remainder) min"
        }
        return "\(normalized) min"
    }
}
