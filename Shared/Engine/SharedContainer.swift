import Foundation

@MainActor
public final class SharedContainer {
    public let staticService: FGCStaticService
    public let realtimeService: FGCRealtimeService
    public let tmbCredentials: TMBCredentialProvider
    public let tmbStaticService: TMBStaticService
    public let tmbRealtimeService: TMBiBusService
    public let calendarService: CalendarService
    public let engine: CommuteEngine
    public let store: PingStore
    public let gtfsUpdateService: GTFSUpdateService
    public let serviceAlertsService: FGCServiceAlertsService
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
        serviceAlertsService = FGCServiceAlertsService()
        tmbCredentials = TMBCredentialProvider(bundle: bundle)
        tmbStaticService = TMBStaticService(zipURL: updateService.bestAvailableTMBZipURL())
        tmbRealtimeService = TMBiBusService(credentials: tmbCredentials)

        // Use downloaded ZIP if available, otherwise fall back to bundled
        let zipURL = updateService.bestAvailableZipURL(bundledURL: bundledZipURL)

        staticService = FGCStaticService(zipURL: zipURL)
        realtimeService = FGCRealtimeService()
        calendarService = CalendarService(staticService: staticService)
        locationService = LocationService()
        walkingETAService = WalkingETAService()

        var storeRef: PingStore?
        engine = CommuteEngine(
            staticService: staticService,
            realtimeService: realtimeService,
            calendarService: calendarService,
            walkingMinutesProvider: { @Sendable in
                await MainActor.run { storeRef?.walkingMinutes ?? 0 }
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
            serviceAlertsService: serviceAlertsService,
            tmbStaticService: tmbStaticService,
            tmbRealtimeService: tmbRealtimeService,
            tmbCredentials: tmbCredentials,
            gtfsUpdateService: updateService,
            bundledGTFSURL: bundledZipURL
        )
        store = pingStore
        storeRef = pingStore
    }
}
