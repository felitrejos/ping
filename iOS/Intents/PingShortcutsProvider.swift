import AppIntents
import Foundation

struct PingShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDepartureIntent(),
            phrases: [
                "Next train in \(.applicationName)",
                "Next train near me in \(.applicationName)"
            ],
            shortTitle: "Next Departure",
            systemImageName: "tram.fill"
        )

        AppShortcut(
            intent: DeparturesBetweenStopsIntent(),
            phrases: [
                "Departures from \(\.$origin) in \(.applicationName)",
                "Show trains to \(\.$destination) in \(.applicationName)"
            ],
            shortTitle: "Between Stations",
            systemImageName: "arrow.triangle.branch"
        )
    }
}
