import Foundation

public actor CommuteEngine {
    private let staticService: StaticServiceProviding
    private let realtimeService: RealtimeServiceProviding
    private let calendarService: CalendarServiceProviding
    private let clock: Clock
    private let walkingMinutesProvider: @Sendable () -> Int
    private let bufferMinutesProvider: @Sendable () -> Int

    public init(
        staticService: StaticServiceProviding,
        realtimeService: RealtimeServiceProviding,
        calendarService: CalendarServiceProviding,
        clock: Clock = SystemClock(),
        walkingMinutesProvider: @escaping @Sendable () -> Int = { UserSettings.walkingMinutes() },
        bufferMinutesProvider: @escaping @Sendable () -> Int = { UserSettings.bufferMinutes() }
    ) {
        self.staticService = staticService
        self.realtimeService = realtimeService
        self.calendarService = calendarService
        self.clock = clock
        self.walkingMinutesProvider = walkingMinutesProvider
        self.bufferMinutesProvider = bufferMinutesProvider
    }

    public func refresh() async {
        await realtimeService.refresh()
    }

    public func nextDeparture(from origin: StopID, to destination: StopID) async throws -> LiveDeparture? {
        try await upcomingDepartures(from: origin, to: destination, limit: 1).first
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
        guard let homeStopID = await calendarService.userHomeStation() else {
            return []
        }

        let commuteEvents = try await calendarService.upcomingCommutes(within: hours)
        var plans: [CommutePlan] = []
        for event in commuteEvents {
            guard let destination = event.resolvedStation else {
                continue
            }
            guard let plan = try await plan(for: event, origin: homeStopID, destination: destination) else {
                continue
            }
            plans.append(plan)
        }
        return plans.sorted { $0.recommendedDeparture < $1.recommendedDeparture }
    }

    private func plan(for event: CommuteEvent, origin: StopID, destination: StopID) async throws -> CommutePlan? {
        let departures = try await staticService.departuresBetween(origin: origin, destination: destination, after: clock.now)
        guard !departures.isEmpty else {
            return nil
        }

        var liveOptions: [LiveDeparture] = []
        for departure in departures.prefix(5) {
            let delaySeconds = await realtimeService.delayFor(tripID: departure.tripID, stopID: origin) ?? 0
            let effectiveDeparture = departure.departureTime.addingTimeInterval(TimeInterval(delaySeconds))
            let minutesUntil = max(0, Int((effectiveDeparture.timeIntervalSince(clock.now) / 60.0).rounded(.awayFromZero)))
            liveOptions.append(
                LiveDeparture(
                    scheduledTime: departure.departureTime,
                    delaySeconds: delaySeconds,
                    trainLabel: "\(departure.routeShortName) \(departure.headsign)",
                    minutesUntilDeparture: minutesUntil,
                    tripID: departure.tripID,
                    destinationStopID: destination
                )
            )
        }

        let bufferSeconds = TimeInterval(bufferMinutesProvider() * 60)
        let walkingSeconds = TimeInterval(walkingMinutesProvider() * 60)
        let viableOption = liveOptions.first(where: { liveDeparture in
            let leaveBy = liveDeparture.effectiveDepartureTime.addingTimeInterval(-(walkingSeconds + bufferSeconds))
            return leaveBy > clock.now
        }) ?? liveOptions.first

        guard let viableOption else {
            return nil
        }

        let recommendedDeparture = viableOption.effectiveDepartureTime.addingTimeInterval(-(walkingSeconds + bufferSeconds))
        return CommutePlan(
            calendarEvent: event,
            recommendedDeparture: recommendedDeparture,
            trainOptions: liveOptions
        )
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            let value = try await transform(element)
            result.append(value)
        }
        return result
    }
}
