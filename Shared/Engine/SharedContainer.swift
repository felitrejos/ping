import Foundation

@MainActor
public final class SharedContainer {
    public let staticService: FGCStaticService
    public let realtimeService: FGCRealtimeService
    public let calendarService: CalendarService
    public let engine: CommuteEngine
    public let store: PingStore
    public let gtfsUpdateService: GTFSUpdateService
    public let geoTrainService: GeoTrainService
    public let locationService: LocationService
    public let walkingETAService: WalkingETAService

    public init(bundle: Bundle = .main) {
        UserSettings.migrateLegacyDefaultRouteIfNeeded()

        let bundledZipURL = bundle.url(
            forResource: Constants.bundledStaticGTFSName,
            withExtension: Constants.bundledStaticGTFSExtension
        ) ?? URL(fileURLWithPath: "/tmp/google_transit.zip")

        let updateService = GTFSUpdateService()
        gtfsUpdateService = updateService
        geoTrainService = GeoTrainService()

        // Use downloaded ZIP if available, otherwise fall back to bundled
        let zipURL = updateService.bestAvailableZipURL(bundledURL: bundledZipURL)

        staticService = FGCStaticService(zipURL: zipURL)
        realtimeService = FGCRealtimeService()
        calendarService = CalendarService(staticService: staticService)
        locationService = LocationService()
        walkingETAService = WalkingETAService()

        // The store owns the dynamic walking ETA. The engine reads it via a closure
        // so that bestCatchableDeparture and commute plans use the live value.
        var storeRef: PingStore?
        engine = CommuteEngine(
            staticService: staticService,
            realtimeService: realtimeService,
            calendarService: calendarService,
            walkingMinutesProvider: { @Sendable in
                await MainActor.run { storeRef?.walkingMinutes ?? UserSettings.walkingMinutes() }
            },
            originCandidatesProvider: { @Sendable in
                await MainActor.run {
                    guard
                        let storeRef,
                        let userLocation = storeRef.userLocation
                    else {
                        return []
                    }

                    return storeRef.availableStops
                        .compactMap { stop -> (id: StopID, distanceSquared: Double)? in
                            guard let coordinate = stop.coordinate else {
                                return nil
                            }

                            let latitudeDelta = coordinate.latitude - userLocation.latitude
                            let longitudeDelta = coordinate.longitude - userLocation.longitude
                            let distanceSquared = latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
                            return (id: stop.id, distanceSquared: distanceSquared)
                        }
                        .sorted { $0.distanceSquared < $1.distanceSquared }
                        .prefix(10)
                        .map(\.id)
                }
            }
        )
        let pingStore = PingStore(
            engine: engine,
            staticService: staticService,
            calendarService: calendarService,
            realtimeService: realtimeService,
            locationService: locationService,
            walkingETAService: walkingETAService,
            geoTrainService: geoTrainService,
            gtfsUpdateService: updateService,
            bundledGTFSURL: bundledZipURL
        )
        store = pingStore
        storeRef = pingStore
    }
}
