import AppIntents
import Foundation

struct NextDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Departure"
    static let description = IntentDescription("Shows the next departures from your closest FGC station.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let origin = try await PingIntentSupport.nearestStation() else {
            let message = "I couldn't find your closest station. Enable location access for Ping and try again."
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
            let message = "No upcoming departures found from \(origin.name) right now."
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        let primaryText = "\(first.departure.routeShortName) to \(first.departure.headsign) in \(first.minutes) min"
        let extraText = departures
            .dropFirst()
            .map { item in
                "\(item.departure.routeShortName) to \(item.departure.headsign) in \(item.minutes) min"
            }
            .joined(separator: ", ")

        let message: String
        if extraText.isEmpty {
            message = "Closest station is \(origin.name). Next train: \(primaryText)."
        } else {
            message = "Closest station is \(origin.name). Next trains: \(primaryText), then \(extraText)."
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
