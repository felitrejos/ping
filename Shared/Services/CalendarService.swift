import EventKit
import Foundation

public actor CalendarService: CalendarServiceProviding {
    private let eventProvider: CalendarEventProviding
    private let staticService: StaticServiceProviding
    private let defaults: UserDefaults

    public init(
        eventProvider: CalendarEventProviding = EventKitCalendarProvider(),
        staticService: StaticServiceProviding,
        defaults: UserDefaults = .standard
    ) {
        self.eventProvider = eventProvider
        self.staticService = staticService
        self.defaults = defaults
    }

    public func authorizationStatus() async -> CalendarAuthorizationState {
        eventProvider.authorizationStatus()
    }

    public func requestAccess() async -> CalendarAuthorizationState {
        await eventProvider.requestAccess()
    }

    public func upcomingCommutes(within hours: Int) async throws -> [CommuteEvent] {
        let status = eventProvider.authorizationStatus()
        guard status.isAuthorized else {
            return []
        }

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(hours) * 3_600)
        let records = try await eventProvider.fetchEvents(from: startDate, to: endDate)
        let stops = try await staticService.allStops()

        return records
            .sorted { $0.startDate < $1.startDate }
            .map { record in
                CommuteEvent(
                    id: record.id,
                    title: record.title,
                    startDate: record.startDate,
                    location: record.location,
                    resolvedStation: resolveStation(for: record.location, from: stops)
                )
            }
    }

    public func userHomeStation() async -> StopID? {
        UserSettings.homeStationID(defaults: defaults)
    }

    public func setUserHomeStation(_ stopID: StopID?) async {
        UserSettings.setHomeStationID(stopID, defaults: defaults)
    }

    private func resolveStation(for location: String?, from stops: [Stop]) -> StopID? {
        guard let location, !location.isEmpty else {
            return nil
        }

        let normalizedLocation = normalize(location)
        return stops.first(where: { stop in
            let normalizedStop = normalize(stop.name)
            return normalizedLocation.localizedStandardContains(normalizedStop)
                || normalizedStop.localizedStandardContains(normalizedLocation)
        })?.id
    }

    private func normalize(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct EventKitCalendarProvider: CalendarEventProviding {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func authorizationStatus() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .fullAccess:
            .fullAccess
        case .writeOnly:
            .writeOnly
        @unknown default:
            .denied
        }
    }

    public func requestAccess() async -> CalendarAuthorizationState {
        do {
            if #available(macOS 14.0, iOS 17.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            return authorizationStatus()
        }

        return authorizationStatus()
    }

    public func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEventRecord] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).map { event in
            CalendarEventRecord(
                id: event.calendarItemIdentifier,
                title: event.title,
                startDate: event.startDate,
                location: event.location
            )
        }
    }
}
