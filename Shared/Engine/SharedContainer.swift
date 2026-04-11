import Foundation

@MainActor
public final class SharedContainer {
    public let staticService: FGCStaticService
    public let realtimeService: FGCRealtimeService
    public let calendarService: CalendarService
    public let engine: CommuteEngine
    public let store: MakoStore

    public init(bundle: Bundle = .main) {
        let zipURL = bundle.url(
            forResource: Constants.bundledStaticGTFSName,
            withExtension: Constants.bundledStaticGTFSExtension
        ) ?? URL(fileURLWithPath: "/tmp/google_transit.zip")

        staticService = FGCStaticService(zipURL: zipURL)
        realtimeService = FGCRealtimeService()
        calendarService = CalendarService(staticService: staticService)
        engine = CommuteEngine(
            staticService: staticService,
            realtimeService: realtimeService,
            calendarService: calendarService
        )
        store = MakoStore(
            engine: engine,
            staticService: staticService,
            calendarService: calendarService,
            realtimeService: realtimeService
        )
    }
}
