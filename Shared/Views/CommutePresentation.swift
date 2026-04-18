import Foundation

public enum CommutePresentation {
    public static func calendarRouteDetail(for plan: CommutePlan, availableStops: [Stop]) -> String? {
        // Each fragment is pre-localized here because the caller renders the combined result via
        // `Text(_ verbatim:)`. Keeping the join character (" -> ") as ASCII keeps the caption
        // short and unambiguous across languages; we don't localize the separator itself.
        var parts: [String] = []

        if let location = plan.calendarEvent.location, !location.isEmpty {
            parts.append(location)
        }

        if let originName = stationName(for: plan.originStationID, in: availableStops) {
            parts.append(String(
                localized: "from \(originName)",
                comment: "Calendar event route fragment. Placeholder is the origin station name."
            ))
        }

        if let destinationName = stationName(for: plan.destinationStationID, in: availableStops) {
            let resolvedStationID = plan.calendarEvent.resolvedStation
            let isFallbackDestination = resolvedStationID != nil && resolvedStationID != plan.destinationStationID
            if isFallbackDestination {
                parts.append(String(
                    localized: "best reachable station: \(destinationName)",
                    comment: "Fragment used when we couldn't route directly to the event's station."
                ))
            } else {
                parts.append(String(
                    localized: "destination station: \(destinationName)",
                    comment: "Fragment identifying the destination station we're routing to."
                ))
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " -> ")
    }

    private static func stationName(for stopID: StopID, in stops: [Stop]) -> String? {
        stops.first(where: { $0.id == stopID })?.name
    }
}
