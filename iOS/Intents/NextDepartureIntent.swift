import AppIntents
import Foundation

struct NextDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Departure"
    static let description = IntentDescription("Shows the next departures from your closest FGC station.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let origin = try await PingIntentSupport.nearestStation() else {
            let message = String(
                localized: "I couldn't find your closest station. Enable location access for Ping and try again.",
                comment: "Siri response when the device has no usable location."
            )
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        let container = await PingIntentSupport.container()
        let now = Date()
        let scheduled = try await container.staticService.departuresFrom(origin: origin.id, after: now, limit: 8)
        let enriched = await scheduled.asyncMap { departure -> (departure: TrainDeparture, effectiveDeparture: Date, minutes: Int) in
            let delaySeconds = await container.realtimeService.delayFor(tripID: departure.tripID, stopID: origin.id) ?? 0
            let effectiveDeparture = departure.departureTime.addingTimeInterval(TimeInterval(delaySeconds))
            let minutes = max(0, Int((effectiveDeparture.timeIntervalSince(now) / 60.0).rounded(.awayFromZero)))
            return (departure, effectiveDeparture, minutes)
        }
        let departures = enriched
            .filter { $0.1 >= now }
            .sorted { $0.1 < $1.1 }
            .prefix(3)

        guard let first = departures.first else {
            let message = String(
                localized: "No upcoming departures found from \(origin.name) right now.",
                comment: "Siri response when there are no upcoming departures."
            )
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        let formatDeparture: (TrainDeparture, Int) -> String = { dep, minutes in
            String(
                localized: "\(dep.routeShortName) to \(dep.headsign) in \(minutes) min",
                comment: "Siri-friendly train summary. Placeholders: route code, headsign, minutes until departure."
            )
        }
        let primaryText = formatDeparture(first.departure, first.minutes)
        let extraText = departures
            .dropFirst()
            .map { formatDeparture($0.departure, $0.minutes) }
            .joined(separator: ", ")

        let message: String
        if extraText.isEmpty {
            message = String(
                localized: "Closest station is \(origin.name). Next train: \(primaryText).",
                comment: "Siri response summarising the single next departure."
            )
        } else {
            message = String(
                localized: "Closest station is \(origin.name). Next trains: \(primaryText), then \(extraText).",
                comment: "Siri response summarising the next few departures."
            )
        }

        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: @Sendable (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self {
            let value = await transform(element)
            result.append(value)
        }
        return result
    }
}
