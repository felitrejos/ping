import CoreLocation
import MapKit
import SwiftUI

struct FGCMapView: View {
    @Environment(PingStore.self) private var store
    @State private var position: MapCameraPosition = .automatic
    @State private var routeStops: [Stop] = []
    @State private var walkingRoute: MKPolyline?
    @State private var selectedStation: Stop?
    @State private var originID: StopID?
    @State private var destinationID: StopID?
    @State private var isTMBOverlayEnabled = UserSettings.tmbEnabled()
    @State private var shouldShowAllStations = false
    @State private var lastWalkingRouteRequestKey: WalkingRouteRequestKey?
    @State private var lastCameraRegion: MKCoordinateRegion?
    @State private var visibleTMBStops: [TMBStop] = []
    @State private var selectedTMBStop: TMBStop?
    @State private var tmbArrivals: [TMBArrival] = []
    @State private var tmbLoadState: TMBLoadState = .idle

    private let tmbZoomLatitudeDeltaThreshold: CLLocationDegrees = 0.02
    private let maxVisibleTMBStops = 300

    private var stationsWithCoordinates: [Stop] {
        store.availableStops.filter { $0.coordinate != nil }
    }

    private var visibleStations: [Stop] {
        guard !shouldShowAllStations else {
            return stationsWithCoordinates
        }

        var prioritized: [Stop] = []
        var seen = Set<StopID>()
        let anchors = [originStop, destinationStop] + routeStops + closestStations
        for station in anchors.compactMap({ $0 }) where seen.insert(station.id).inserted {
            prioritized.append(station)
        }

        if prioritized.count >= 40 {
            return prioritized
        }

        for station in stationsWithCoordinates where seen.insert(station.id).inserted {
            prioritized.append(station)
            if prioritized.count >= 40 {
                break
            }
        }

        return prioritized
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        store.userLocation?.mapCoordinate
    }

    private var originStop: Stop? {
        guard let originID else { return nil }
        return stationsWithCoordinates.first { $0.id == originID }
    }

    private var destinationStop: Stop? {
        guard let destinationID else { return nil }
        return stationsWithCoordinates.first { $0.id == destinationID }
    }

    private var hasActiveCommuteContext: Bool {
        store.nextDeparture != nil || store.nextCommute != nil
    }

    private var closestStations: [Stop] {
        guard let userCoordinate else {
            return []
        }

        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return stationsWithCoordinates
            .sorted { first, second in
                first.distance(from: userLocation) < second.distance(from: userLocation)
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Map(position: $position) {
            if let walkingRoute {
                MapPolyline(walkingRoute)
                    .stroke(.blue, lineWidth: 5)
            }

            ForEach(visibleStations) { station in
                if let coordinate = station.coordinate?.mapCoordinate {
                    Annotation(station.name, coordinate: coordinate) {
                        Button {
                            clearSelectedTMBStop()
                            selectedStation = station
                        } label: {
                            StationMarker(
                                station: station,
                                role: role(for: station),
                                isNearby: userCoordinate != nil && closestStations.contains(where: { $0.id == station.id })
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isTMBOverlayEnabled {
                ForEach(visibleTMBStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate.mapCoordinate) {
                        Button {
                            clearSelectedStation()
                            selectedTMBStop = stop
                            Task {
                                await loadTMBArrivals(for: stop)
                            }
                        } label: {
                            TMBBusStopMarker(stop: stop)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .including([.publicTransport]), showsTraffic: false))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            lastCameraRegion = context.region
            Task {
                await refreshVisibleTMBStops(for: context.region)
            }
        }
        .overlay(alignment: .topLeading) {
            mapOverlayControls
                .padding(.top, 12)
                .padding(.leading, 14)
        }
        .safeAreaInset(edge: .bottom) {
            MapStatusPanel(
                origin: originStop,
                destination: destinationStop,
                nextDeparture: store.nextDeparture,
                walkMinutes: store.walkingMinutes,
                isUsingLiveLocation: store.isUsingLiveLocation,
                routeStops: routeStops,
                closestStations: closestStations,
                hasUserLocation: userCoordinate != nil,
                selectedStation: selectedStation,
                selectedBusStop: selectedTMBStop,
                busArrivals: tmbArrivals,
                busLoadState: tmbLoadState,
                onDismissStation: clearSelectedStation,
                onDismissBusStop: clearSelectedTMBStop,
                onSetOrigin: { station in
                    clearSelectedStation()
                    Task {
                        await store.setHomeStation(station.id)
                        await reloadMapData()
                    }
                },
                onSetDestination: { station in
                    clearSelectedStation()
                    Task {
                        await store.setDestinationStation(station.id)
                        await reloadMapData()
                    }
                },
                onRetryBusArrivals: {
                    guard let selectedTMBStop else {
                        return
                    }

                    Task {
                        await loadTMBArrivals(for: selectedTMBStop)
                    }
                }
            )
        }
        .task {
            await reloadMapData()
            scheduleFullStationLoad()
            isTMBOverlayEnabled = store.isTMBLayerPreferred
            if let lastCameraRegion {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
        .refreshable {
            await store.refresh()
            await reloadMapData()
            scheduleFullStationLoad()
            if let lastCameraRegion {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
        .onChange(of: store.availableStops) { _, _ in
            shouldShowAllStations = false
            Task {
                await reloadMapData()
                scheduleFullStationLoad()
                if let lastCameraRegion {
                    await refreshVisibleTMBStops(for: lastCameraRegion)
                }
            }
        }
        .onChange(of: store.userLocation) { _, _ in
            Task { await updateWalkingRoute() }
        }
        .onChange(of: hasActiveCommuteContext) { _, _ in
            Task { await updateWalkingRoute() }
        }
        .onChange(of: store.homeStationID) { _, _ in
            Task { await reloadMapData() }
        }
        .onChange(of: store.destinationStationID) { _, _ in
            Task { await reloadMapData() }
        }
        .onChange(of: isTMBOverlayEnabled) { _, isEnabled in
            store.setTMBEnabled(isEnabled)
            if !isEnabled {
                clearSelectedTMBStop()
                visibleTMBStops = []
                return
            }

            guard let lastCameraRegion else {
                return
            }

            Task {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
    }

    private func scheduleFullStationLoad() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                shouldShowAllStations = true
            }
        }
    }

    @ViewBuilder
    private var mapOverlayControls: some View {
        if store.hasTMBCredentials {
            tmbOverlayButton
        }
    }

    @ViewBuilder
    private var tmbOverlayButton: some View {
        Button {
            isTMBOverlayEnabled.toggle()
        } label: {
            ZStack {
                Image(systemName: "bus.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)

                if !isTMBOverlayEnabled {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 28, height: 2.5)
                        .rotationEffect(.degrees(-38))
                }
            }
            .foregroundStyle(isTMBOverlayEnabled ? .primary : .secondary)
        }
        .accessibilityLabel(isTMBOverlayEnabled ? "Disable TMB bus overlay" : "Enable TMB bus overlay")
        .accessibilityHint("Shows nearby TMB bus stops on the map when zoomed in")
        .ifAvailableGlassMapButton()
    }

    private func clearSelectedStation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStation = nil
        }
    }

    private func clearSelectedTMBStop() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTMBStop = nil
            tmbArrivals = []
            tmbLoadState = .idle
        }
    }

    private func role(for station: Stop) -> StationRole {
        if station.id == originID {
            return .origin
        }
        if station.id == destinationID {
            return .destination
        }
        if routeStops.contains(where: { $0.id == station.id }) {
            return .route
        }

        return .nearby
    }

    private func reloadMapData() async {
        originID = await store.selectedHomeStationID()
        destinationID = await store.selectedDestinationStationID()
        routeStops = await store.configuredRouteStops()
        await updateWalkingRoute()
        updateCamera()
    }

    private func refreshVisibleTMBStops(for region: MKCoordinateRegion) async {
        guard isTMBOverlayEnabled, store.isTMBEnabled else {
            await MainActor.run {
                visibleTMBStops = []
            }
            return
        }

        guard region.span.latitudeDelta <= tmbZoomLatitudeDeltaThreshold else {
            await MainActor.run {
                visibleTMBStops = []
            }
            return
        }

        let box = TMBBoundingBox(region: region)
        let center = TransitCoordinate(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let stops = await store.tmbStops(in: box)
        let sortedStops = stops.sorted { first, second in
            first.coordinate.distanceSquared(to: center) < second.coordinate.distanceSquared(to: center)
        }

        await MainActor.run {
            visibleTMBStops = Array(sortedStops.prefix(maxVisibleTMBStops))
        }
    }

    private func loadTMBArrivals(for stop: TMBStop) async {
        tmbLoadState = .loading
        let result = await store.tmbArrivals(for: stop)
        switch result {
        case let .success(arrivals):
            tmbArrivals = arrivals
            tmbLoadState = .idle
        case let .failure(error):
            tmbArrivals = []
            tmbLoadState = .error(error.displayMessage)
        }
    }

    private func updateWalkingRoute() async {
        guard hasActiveCommuteContext else {
            lastWalkingRouteRequestKey = nil
            walkingRoute = nil
            return
        }

        guard
            let userCoordinate,
            let originCoordinate = originStop?.coordinate?.mapCoordinate
        else {
            lastWalkingRouteRequestKey = nil
            walkingRoute = nil
            return
        }

        let requestKey = WalkingRouteRequestKey(source: userCoordinate, destination: originCoordinate)
        guard requestKey != lastWalkingRouteRequestKey else {
            return
        }

        lastWalkingRouteRequestKey = requestKey
        let route = await Self.walkingRoute(from: userCoordinate, to: originCoordinate)
        guard requestKey == lastWalkingRouteRequestKey else {
            return
        }

        walkingRoute = route
    }

    private func updateCamera() {
        let routeCoordinates = routeStops.compactMap { $0.coordinate?.mapCoordinate }
        var coordinates = routeCoordinates
        if let userCoordinate {
            coordinates.append(userCoordinate)
        }

        guard !coordinates.isEmpty else {
            position = .automatic
            return
        }

        let region = MKCoordinateRegion(coordinates: coordinates, padding: 0.012)
        lastCameraRegion = region
        position = .region(region)
    }

    private static func walkingRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> MKPolyline? {
        let request = MKDirections.Request()
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = .walking

        do {
            return try await MKDirections(request: request).calculate().routes.first?.polyline
        } catch {
            return nil
        }
    }

    private static func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return MKMapItem(location: location, address: nil)
    }
}

private struct WalkingRouteRequestKey: Equatable {
    let sourceLatitudeBucket: Int
    let sourceLongitudeBucket: Int
    let destinationLatitudeBucket: Int
    let destinationLongitudeBucket: Int

    init(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) {
        sourceLatitudeBucket = Self.bucket(source.latitude)
        sourceLongitudeBucket = Self.bucket(source.longitude)
        destinationLatitudeBucket = Self.bucket(destination.latitude)
        destinationLongitudeBucket = Self.bucket(destination.longitude)
    }

    private static func bucket(_ value: CLLocationDegrees) -> Int {
        Int((value * 10_000).rounded())
    }
}

private enum StationRole {
    case origin
    case destination
    case route
    case nearby

    var tint: Color {
        switch self {
        case .origin: .blue
        case .destination, .route: .green
        case .nearby: .white
        }
    }

    var symbol: String {
        self == .nearby ? "mappin.circle" : "mappin.circle.fill"
    }
}

private struct StationMarker: View {
    let station: Stop
    let role: StationRole
    let isNearby: Bool

    var body: some View {
        Image(systemName: role.symbol)
            .font(.system(size: role == .nearby ? 12 : 14, weight: .bold))
            .foregroundStyle(role == .nearby ? .blue : .white)
            .frame(width: isNearby || role != .nearby ? 32 : 24, height: isNearby || role != .nearby ? 32 : 24)
            .background(role.tint, in: Circle())
            .overlay {
                Circle()
                    .stroke(.blue.opacity(isNearby ? 0.9 : 0.25), lineWidth: isNearby ? 3 : 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .accessibilityLabel(station.name)
    }
}

private struct MapStatusPanel: View {
    let origin: Stop?
    let destination: Stop?
    let nextDeparture: LiveDeparture?
    let walkMinutes: Int
    let isUsingLiveLocation: Bool
    let routeStops: [Stop]
    let closestStations: [Stop]
    let hasUserLocation: Bool
    let selectedStation: Stop?
    let selectedBusStop: TMBStop?
    let busArrivals: [TMBArrival]
    let busLoadState: TMBLoadState
    let onDismissStation: () -> Void
    let onDismissBusStop: () -> Void
    let onSetOrigin: (Stop) -> Void
    let onSetDestination: (Stop) -> Void
    let onRetryBusArrivals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedBusStop {
                busStopSummary(for: selectedBusStop)
            } else if let selectedStation {
                stationActions(for: selectedStation)
            } else if let nextDeparture {
                activeRouteSummary(nextDeparture)
            } else if let origin, let destination {
                configuredRouteSummary(origin: origin, destination: destination)
            } else {
                nearbySummary
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func activeRouteSummary(_ departure: LiveDeparture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Go to \(origin?.name ?? "the station")", systemImage: isUsingLiveLocation ? "location.fill" : "figure.walk")
                    .font(.headline)
                Spacer()
            }
            HStack {
                Label("Train departs", systemImage: "tram.fill")
                Spacer()
                Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Label("\(walkMinutes) min walk", systemImage: isUsingLiveLocation ? "location.fill" : "figure.walk")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func configuredRouteSummary(origin: Stop, destination: Stop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label("\(origin.name) to \(destination.name)", systemImage: "tram.fill")
                    .font(.headline)
                    .lineLimit(2)

                Spacer()
            }
            Text("\(max(routeStops.count - 1, 0)) station hops from GTFS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var nearbySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nearby FGC stations", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                if hasUserLocation {
                    Text("Using location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            if hasUserLocation {
                Text(closestStations.map(\.name).prefix(3).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Location is off, so nearby stations are unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func stationActions(for station: Stop) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(station.name, systemImage: "tram.fill")
                .font(.headline)
                .lineLimit(2)
                .padding(.trailing, 54)
                .padding(.bottom, 4)

            HStack(spacing: 10) {
                stationActionButton("From here", systemImage: "target", isPrimary: true) {
                    onSetOrigin(station)
                }

                stationActionButton("To here", systemImage: "flag.checkered", isPrimary: false) {
                    onSetDestination(station)
                }
            }
            .padding(.top, 10)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismissStation) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close station actions")
            .offset(x: 6, y: -10)
        }
    }

    private func busStopSummary(for stop: TMBStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(stop.name, systemImage: "bus.fill")
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                if let code = stop.code, !code.isEmpty {
                    Text("#\(code)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            switch busLoadState {
            case .idle:
                if busArrivals.isEmpty {
                    Text("No upcoming buses at this stop.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(busArrivals.prefix(5).enumerated()), id: \.offset) { _, arrival in
                            HStack(spacing: 8) {
                                Text(arrival.routeShortName)
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange.opacity(0.16), in: Capsule())

                                Text(arrival.destination)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(arrival.minutesAway) min")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading arrivals…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case let .error(message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry", action: onRetryBusArrivals)
                        .buttonStyle(.bordered)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismissBusStop) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close bus stop details")
            .offset(x: 4, y: -8)
        }
    }

    @ViewBuilder
    private func stationActionButton(
        _ title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        if #available(iOS 26.0, *) {
            if isPrimary { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
        } else {
            if isPrimary { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        }
    }
}

private struct TMBBusStopMarker: View {
    let stop: TMBStop

    var body: some View {
        Image(systemName: "bus.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.orange, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 1.1)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .accessibilityLabel(stop.name)
    }
}

private enum TMBLoadState: Equatable {
    case idle
    case loading
    case error(String)
}

private extension Stop {
    func distance(from location: CLLocation) -> CLLocationDistance {
        guard let coordinate else {
            return .greatestFiniteMagnitude
        }

        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: location)
    }
}

private extension TransitCoordinate {
    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceSquared(to other: TransitCoordinate) -> Double {
        let latitudeDelta = latitude - other.latitude
        let longitudeDelta = longitude - other.longitude
        return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
    }
}

private extension TMBBoundingBox {
    init(region: MKCoordinateRegion) {
        let latitudeDelta = region.span.latitudeDelta / 2
        let longitudeDelta = region.span.longitudeDelta / 2
        self.init(
            minLatitude: region.center.latitude - latitudeDelta,
            maxLatitude: region.center.latitude + latitudeDelta,
            minLongitude: region.center.longitude - longitudeDelta,
            maxLongitude: region.center.longitude + longitudeDelta
        )
    }
}

private extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D], padding: CLLocationDegrees) {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? 41.387
        let maxLatitude = latitudes.max() ?? 41.387
        let minLongitude = longitudes.min() ?? 2.17
        let maxLongitude = longitudes.max() ?? 2.17
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) + padding, 0.018),
            longitudeDelta: max((maxLongitude - minLongitude) + padding, 0.018)
        )

        self.init(center: center, span: span)
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableGlassMapButton() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.bordered)
                .background(.regularMaterial, in: Circle())
        }
    }
}
