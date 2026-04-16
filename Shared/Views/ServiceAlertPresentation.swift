import SwiftUI

/// Presentation helpers for `ServiceAlert` values, shared across iOS, macOS, and Widgets.
public enum ServiceAlertPresentation {
    public static func rank(for severity: ServiceAlertSeverity) -> Int {
        switch severity {
        case .info:
            0
        case .minor:
            1
        case .major:
            2
        case .closure:
            3
        }
    }

    public static func color(for severity: ServiceAlertSeverity) -> Color {
        switch severity {
        case .info:
            .blue
        case .minor:
            .yellow
        case .major:
            .orange
        case .closure:
            .red
        }
    }

    public static func label(for severity: ServiceAlertSeverity) -> String {
        switch severity {
        case .info:
            "Info"
        case .minor:
            "Minor"
        case .major:
            "Major"
        case .closure:
            "Closure"
        }
    }

    /// Filters out purely informational alerts and returns the subset that warrants user attention.
    public static func actionableAlerts(from alerts: [ServiceAlert]) -> [ServiceAlert] {
        alerts.filter { $0.severity != .info }
    }

    /// Highest-severity alert in a list, suitable for a primary summary card.
    public static func primaryAlert(from alerts: [ServiceAlert]) -> ServiceAlert? {
        alerts.max { rank(for: $0.severity) < rank(for: $1.severity) }
    }

    /// Collapses a list of alerts into one badge per affected line, keeping the highest severity seen.
    public static func lineStatusRows(from alerts: [ServiceAlert]) -> [LineStatusRow] {
        var severityByLine: [String: ServiceAlertSeverity] = [:]

        for alert in alerts {
            for line in alert.affectedLines {
                if let current = severityByLine[line] {
                    if rank(for: alert.severity) > rank(for: current) {
                        severityByLine[line] = alert.severity
                    }
                } else {
                    severityByLine[line] = alert.severity
                }
            }
        }

        return severityByLine
            .map { LineStatusRow(line: $0.key, severity: $0.value) }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
    }
}

public struct LineStatusRow: Identifiable, Equatable, Sendable {
    public let line: String
    public let severity: ServiceAlertSeverity

    public init(line: String, severity: ServiceAlertSeverity) {
        self.line = line
        self.severity = severity
    }

    public var id: String { line }
}

/// Shared "Updated X ago" caption that warns once alerts are older than a threshold.
public struct AlertsFreshnessCaption: View {
    private let lastUpdated: Date
    private let staleThreshold: TimeInterval

    public init(lastUpdated: Date, staleThreshold: TimeInterval = 15 * 60) {
        self.lastUpdated = lastUpdated
        self.staleThreshold = staleThreshold
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let isStale = timeline.date.timeIntervalSince(lastUpdated) >= staleThreshold

            HStack(spacing: 0) {
                Text("Updated ")
                Text(lastUpdated, style: .relative)
                if isStale {
                    Text(" · may be outdated")
                }
            }
            .font(.caption2)
            .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}
