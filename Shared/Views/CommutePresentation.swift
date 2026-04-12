import Foundation

public enum CommutePresentation {
    public static func calendarRouteDetail(for plan: CommutePlan, availableStops: [Stop]) -> String? {
        var parts: [String] = []

        if let location = plan.calendarEvent.location, !location.isEmpty {
            parts.append(location)
        }

        if let originName = stationName(for: plan.originStationID, in: availableStops) {
            parts.append("from \(originName)")
        }

        if let destinationName = stationName(for: plan.destinationStationID, in: availableStops) {
            let resolvedStationID = plan.calendarEvent.resolvedStation
            let isFallbackDestination = resolvedStationID != nil && resolvedStationID != plan.destinationStationID
            if isFallbackDestination {
                parts.append("best reachable station: \(destinationName)")
            } else {
                parts.append("destination station: \(destinationName)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " -> ")
    }

    private static func stationName(for stopID: StopID, in stops: [Stop]) -> String? {
        stops.first(where: { $0.id == stopID })?.name
    }
}
