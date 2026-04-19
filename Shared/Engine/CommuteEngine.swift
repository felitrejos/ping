import Foundation

public actor CommuteEngine {
    private let staticService: StaticServiceProviding
    private let realtimeService: RealtimeServiceProviding
    private let calendarService: CalendarServiceProviding
    private let clock: Clock
    private let walkingMinutesProvider: @Sendable () async -> Int
    private let bufferMinutesProvider: @Sendable () -> Int
    private let originCandidatesProvider: (@Sendable () async -> [StopID])?

    public init(
        staticService: StaticServiceProviding,
        realtimeService: RealtimeServiceProviding,
        calendarService: CalendarServiceProviding,
        clock: Clock = SystemClock(),
        walkingMinutesProvider: @escaping @Sendable () async -> Int = { UserSettings.walkingMinutes() },
        bufferMinutesProvider: @escaping @Sendable () -> Int = { UserSettings.bufferMinutes() },
        originCandidatesProvider: (@Sendable () async -> [StopID])? = nil
    ) {
        self.staticService = staticService
        self.realtimeService = realtimeService
        self.calendarService = calendarService
        self.clock = clock
        self.walkingMinutesProvider = walkingMinutesProvider
        self.bufferMinutesProvider = bufferMinutesProvider
        self.originCandidatesProvider = originCandidatesProvider
    }

    public func upcomingDepartures(from origin: StopID, to destination: StopID, limit: Int) async throws -> [LiveDeparture] {
        let now = clock.now
        let scheduled = try await staticService.departuresBetween(origin: origin, destination: destination, after: now)
        let upcoming = scheduled.prefix(limit)
        return await upcoming.asyncMap { departure in
            let delaySeconds = await realtimeService.delayFor(tripID: departure.tripID, stopID: origin) ?? 0
            let effectiveTime = departure.departureTime.addingTimeInterval(TimeInterval(delaySeconds))
            let minutes = max(0, Int((effectiveTime.timeIntervalSince(now) / 60.0).rounded(.awayFromZero)))
            return LiveDeparture(
                scheduledTime: departure.departureTime,
                arrivalTime: departure.arrivalTime,
                delaySeconds: delaySeconds,
                trainLabel: "\(departure.routeShortName) \(departure.headsign)",
                minutesUntilDeparture: minutes,
                tripID: departure.tripID,
                destinationStopID: destination
            )
        }
    }

    public func nextCommute() async throws -> CommutePlan? {
        try await commutePlans(within: 12).first
    }

    public func commutePlans(within hours: Int) async throws -> [CommutePlan] {
        let preferredHomeStopID = await calendarService.userHomeStation()
        let extraOriginCandidates = await originCandidatesProvider?() ?? []
        let originCandidates = uniqueOrigins(home: preferredHomeStopID, additional: extraOriginCandidates)
        guard !originCandidates.isEmpty else {
            return []
        }
        let allStops = try await staticService.allStops()

        let commuteEvents = try await calendarService.upcomingCommutes(within: hours)
        var plans: [CommutePlan] = []
        for event in commuteEvents {
            guard let resolvedDestination = event.resolvedStation else {
                continue
            }
            let nearbyDestinations = destinationCandidates(
                around: resolvedDestination,
                from: allStops
            )
            let orderedDestinations = orderedDestinations(
                eventCandidates: event.stationCandidateIDs,
                nearbyDestinations: nearbyDestinations,
                fallback: resolvedDestination
            )
            guard !orderedDestinations.isEmpty else { continue }

            var selectedPlan: CommutePlan?
            for origin in originCandidates {
                for destination in orderedDestinations {
                    if let plan = try await plan(for: event, origin: origin, destination: destination) {
                        selectedPlan = plan
                        break
                    }
                }
                if selectedPlan != nil {
                    break
                }
            }

            if let selectedPlan {
                plans.append(selectedPlan)
            }
        }
        return plans.sorted { $0.recommendedDeparture < $1.recommendedDeparture }
    }

    private func plan(for event: CommuteEvent, origin: StopID, destination: StopID) async throws -> CommutePlan? {
        let departures = try await staticService.departuresBetween(origin: origin, destination: destination, after: clock.now)
        guard !departures.isEmpty else {
            return nil
        }

        var liveOptions: [LiveDeparture] = []
        for departure in departures.prefix(12) {
            let delaySeconds = await realtimeService.delayFor(tripID: departure.tripID, stopID: origin) ?? 0
            let effectiveDeparture = departure.departureTime.addingTimeInterval(TimeInterval(delaySeconds))
            let minutesUntil = max(0, Int((effectiveDeparture.timeIntervalSince(clock.now) / 60.0).rounded(.awayFromZero)))
            liveOptions.append(
                LiveDeparture(
                    scheduledTime: departure.departureTime,
                    arrivalTime: departure.arrivalTime,
                    delaySeconds: delaySeconds,
                    trainLabel: "\(departure.routeShortName) \(departure.headsign)",
                    minutesUntilDeparture: minutesUntil,
                    tripID: departure.tripID,
                    destinationStopID: destination
                )
            )
        }

        let bufferSeconds = TimeInterval(bufferMinutesProvider() * 60)
        let walkingSeconds = TimeInterval(await walkingMinutesProvider() * 60)
        // Walking time from the destination station to the event location, as
        // computed by MapKit when the calendar event was resolved. Falls back
        // to 0 when unknown so we still produce a plan.
        let destinationWalkSeconds = event.destinationWalkingSeconds(for: destination) ?? 0

        // Preferred: the latest train that (a) we can still catch (leave-by is in
        // the future), and (b) arrives at the destination station with enough
        // time to walk to the event plus a buffer. This keeps notifications
        // quiet until it is actually time to leave, rather than firing for the
        // first reachable train hours in advance.
        let targetArrival = event.startDate.addingTimeInterval(-(bufferSeconds + destinationWalkSeconds))
        let onTimeCandidates = liveOptions.filter { option in
            let leaveBy = option.effectiveDepartureTime.addingTimeInterval(-(walkingSeconds + bufferSeconds))
            return leaveBy > clock.now && option.effectiveArrivalTime <= targetArrival
        }

        let viableOption = onTimeCandidates.max(by: { $0.effectiveDepartureTime < $1.effectiveDepartureTime })
            ?? liveOptions.first(where: { option in
                option.effectiveDepartureTime.addingTimeInterval(-(walkingSeconds + bufferSeconds)) > clock.now
            })
            ?? liveOptions.first

        guard let viableOption else {
            return nil
        }

        let recommendedDeparture = viableOption.effectiveDepartureTime.addingTimeInterval(-(walkingSeconds + bufferSeconds))
        return CommutePlan(
            calendarEvent: event,
            originStationID: origin,
            destinationStationID: destination,
            recommendedDeparture: recommendedDeparture,
            trainOptions: liveOptions
        )
    }

    private func uniqueOrigins(home: StopID?, additional: [StopID]) -> [StopID] {
        var ordered: [StopID] = []
        var seen = Set<StopID>()

        for origin in ([home].compactMap { $0 } + additional) where !origin.isEmpty && seen.insert(origin).inserted {
            ordered.append(origin)
        }

        return ordered
    }

    private func destinationCandidates(around resolvedDestination: StopID, from allStops: [Stop]) -> [StopID] {
        guard
            let resolvedStop = allStops.first(where: { $0.id == resolvedDestination }),
            let resolvedCoordinate = resolvedStop.coordinate
        else {
            return [resolvedDestination]
        }

        var ordered = allStops
            .compactMap { stop -> (id: StopID, distanceSquared: Double)? in
                guard let coordinate = stop.coordinate else {
                    return nil
                }
                let latitudeDelta = coordinate.latitude - resolvedCoordinate.latitude
                let longitudeDelta = coordinate.longitude - resolvedCoordinate.longitude
                let distanceSquared = latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
                return (id: stop.id, distanceSquared: distanceSquared)
            }
            .sorted { $0.distanceSquared < $1.distanceSquared }
            .prefix(40)
            .map(\.id)

        if !ordered.contains(resolvedDestination) {
            ordered.insert(resolvedDestination, at: 0)
        }
        return ordered
    }

    private func orderedDestinations(
        eventCandidates: [StopID],
        nearbyDestinations: [StopID],
        fallback: StopID
    ) -> [StopID] {
        var ordered: [StopID] = []
        var seen = Set<StopID>()
        for destination in eventCandidates + nearbyDestinations + [fallback]
            where !destination.isEmpty && seen.insert(destination).inserted {
            ordered.append(destination)
        }
        return ordered
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: @Sendable (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            let value = try await transform(element)
            result.append(value)
        }
        return result
    }
}
