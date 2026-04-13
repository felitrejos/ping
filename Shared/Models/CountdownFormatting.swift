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

    public var plainText: String {
        if isLongForm {
            let trailingValueText = trailingValue ?? "0"
            let trailingUnitText = trailingUnit ?? ""
            return "\(leadingValue)\(leadingUnit) \(trailingValueText)\(trailingUnitText)"
        }

        return "\(leadingValue)\(leadingUnit)"
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
}
