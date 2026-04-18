import AppIntents
import Foundation

struct DeparturesBetweenStopsIntent: AppIntent {
    static let title: LocalizedStringResource = "Departures Between Stations"
    static let description = IntentDescription("Shows upcoming departures between two FGC stations.")
    static let openAppWhenRun = false

    @Parameter(title: "Origin")
    var origin: StopEntity

    @Parameter(title: "Destination")
    var destination: StopEntity

    init() {}

    init(origin: StopEntity, destination: StopEntity) {
        self.origin = origin
        self.destination = destination
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard origin.id != destination.id else {
            let message = String(localized: "Origin and destination must be different stations.")
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        let container = await PingIntentSupport.container()
        let departures = try await container.engine.upcomingDepartures(
            from: origin.id,
            to: destination.id,
            limit: 3
        )

        guard !departures.isEmpty else {
            let message = String(
                localized: "No upcoming departures found from \(origin.name) to \(destination.name).",
                comment: "Siri response when there are no upcoming departures between two stations."
            )
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        let summary = departures
            .map { departure in
                let departureTime = departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened)
                return "\(departureTime) (\(departure.minutesUntilDeparture) min)"
            }
            .joined(separator: ", ")
        let message = String(
            localized: "Next departures from \(origin.name) to \(destination.name): \(summary).",
            comment: "Siri response summarising the next departures between two stations."
        )

        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}
