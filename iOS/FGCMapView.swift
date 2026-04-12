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
    @State private var isGeoTrainOverlayEnabled = false
    @State private var shouldShowAllStations = false
    @State private var displayedGeoTrainCoordinates: [String: TransitCoordinate] = [:]
    @State private var previousGeoTrainCoordinates: [String: TransitCoordinate] = [:]
    @State private var targetGeoTrainCoordinates: [String: TransitCoordinate] = [:]
    @State private var geoTrainInterpolationStart = Date()

    private let geoTrainPollInterval: TimeInterval = 10
    private let geoTrainInterpolationDuration: TimeInterval = 10

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

    private var visibleGeoTrainUnits: [GeoTrainUnit] {
        guard store.hasConfiguredDefaultRoute else {
            return store.geoTrainUnits
        }

        let selectedLine = store.selectedLine.uppercased()
        let lineUnits = store.geoTrainUnits.filter { $0.line.uppercased() == selectedLine }
        guard let expectedDirection = expectedRouteDirection, !lineUnits.isEmpty else {
            return lineUnits
        }

        let directionUnits = lineUnits.filter { $0.direction.uppercased() == expectedDirection }
        return directionUnits.isEmpty ? lineUnits : directionUnits
    }

    private var renderedGeoTrainUnits: [GeoTrainUnit] {
        visibleGeoTrainUnits.map { unit in
            let coordinate = displayedGeoTrainCoordinates[unit.id] ?? unit.coordinate
            return GeoTrainUnit(
                id: unit.id,
                line: unit.line,
                direction: unit.direction,
                originStopID: unit.originStopID,
                destinationStopID: unit.destinationStopID,
                coordinate: coordinate,
                isOnTime: unit.isOnTime
            )
        }
    }

    private var expectedRouteDirection: String? {
        guard
            let originID,
            let destinationID,
            !store.lineStops.isEmpty,
            let originIndex = store.lineStops.firstIndex(where: { $0.id == originID }),
            let destinationIndex = store.lineStops.firstIndex(where: { $0.id == destinationID }),
            originIndex != destinationIndex
        else {
            return nil
        }

        return destinationIndex > originIndex ? "D" : "A"
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

            if isGeoTrainOverlayEnabled {
                ForEach(renderedGeoTrainUnits) { unit in
                    Annotation("", coordinate: unit.coordinate.mapCoordinate) {
                        GeoTrainMarker(unit: unit)
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
        .overlay(alignment: .topLeading) {
            geoTrainOverlayButton
                .padding(.top, 12)
                .padding(.leading, 14)
        }
        .animation(.linear(duration: 1.0), value: renderedGeoTrainUnits)
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
                onDismissStation: clearSelectedStation,
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
                }
            )
        }
        .task {
            await reloadMapData()
            scheduleFullStationLoad()
            if isGeoTrainOverlayEnabled {
                await store.refreshGeoTrainUnits()
                resetGeoTrainInterpolation(with: store.geoTrainUnits)
            }
        }
        .task(id: isGeoTrainOverlayEnabled) {
            guard isGeoTrainOverlayEnabled else {
                return
            }

            var lastRefresh = Date.distantPast
            while !Task.isCancelled, isGeoTrainOverlayEnabled {
                let now = Date()
                if now.timeIntervalSince(lastRefresh) >= geoTrainPollInterval {
                    await store.refreshGeoTrainUnits()
                    lastRefresh = Date()
                }

                advanceGeoTrainInterpolation(at: now)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .refreshable {
            await store.refresh()
            await reloadMapData()
            scheduleFullStationLoad()
            if isGeoTrainOverlayEnabled {
                await store.refreshGeoTrainUnits()
            }
        }
        .onChange(of: store.availableStops) { _, _ in
            shouldShowAllStations = false
            Task {
                await reloadMapData()
                scheduleFullStationLoad()
            }
        }
        .onChange(of: store.userLocation) { _, _ in
            Task { await updateWalkingRoute() }
        }
        .onChange(of: store.nextDeparture) { _, _ in
            Task { await updateWalkingRoute() }
        }
        .onChange(of: store.geoTrainUnits) { _, units in
            updateGeoTrainInterpolationTargets(with: units)
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

    private func resetGeoTrainInterpolation(with units: [GeoTrainUnit]) {
        let coordinates = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.coordinate) })
        displayedGeoTrainCoordinates = coordinates
        previousGeoTrainCoordinates = coordinates
        targetGeoTrainCoordinates = coordinates
        geoTrainInterpolationStart = Date()
    }

    private func updateGeoTrainInterpolationTargets(with units: [GeoTrainUnit]) {
        let nextTargets = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.coordinate) })
        if targetGeoTrainCoordinates.isEmpty {
            resetGeoTrainInterpolation(with: units)
            return
        }

        previousGeoTrainCoordinates = displayedGeoTrainCoordinates
        targetGeoTrainCoordinates = nextTargets
        geoTrainInterpolationStart = Date()

        for id in displayedGeoTrainCoordinates.keys where nextTargets[id] == nil {
            displayedGeoTrainCoordinates.removeValue(forKey: id)
            previousGeoTrainCoordinates.removeValue(forKey: id)
        }
    }

    private func advanceGeoTrainInterpolation(at now: Date) {
        guard !targetGeoTrainCoordinates.isEmpty else {
            return
        }

        let progress = min(1, now.timeIntervalSince(geoTrainInterpolationStart) / geoTrainInterpolationDuration)
        let easedProgress = progress * progress * (3 - 2 * progress)
        var nextDisplayed: [String: TransitCoordinate] = [:]

        for (id, target) in targetGeoTrainCoordinates {
            let start = previousGeoTrainCoordinates[id] ?? target
            nextDisplayed[id] = TransitCoordinate(
                latitude: start.latitude + (target.latitude - start.latitude) * easedProgress,
                longitude: start.longitude + (target.longitude - start.longitude) * easedProgress
            )
        }

        displayedGeoTrainCoordinates = nextDisplayed
    }

    @ViewBuilder
    private var geoTrainOverlayButton: some View {
        Button {
            isGeoTrainOverlayEnabled.toggle()
        } label: {
            ZStack {
                Image(systemName: "tram.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)

                if !isGeoTrainOverlayEnabled {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 28, height: 2.5)
                        .rotationEffect(.degrees(-38))
                }
            }
            .foregroundStyle(isGeoTrainOverlayEnabled ? .primary : .secondary)
        }
        .accessibilityLabel(isGeoTrainOverlayEnabled ? "Disable GeoTrain overlay" : "Enable GeoTrain overlay")
        .accessibilityHint("Shows live train positions on the map")
        .ifAvailableGlassMapButton()
    }

    private func clearSelectedStation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStation = nil
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

    private func updateWalkingRoute() async {
        guard store.nextDeparture != nil || store.nextCommute != nil else {
            walkingRoute = nil
            return
        }

        guard
            let userCoordinate,
            let originCoordinate = originStop?.coordinate?.mapCoordinate
        else {
            walkingRoute = nil
            return
        }

        walkingRoute = await Self.walkingRoute(from: userCoordinate, to: originCoordinate)
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

        position = .region(MKCoordinateRegion(coordinates: coordinates, padding: 0.012))
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
    let onDismissStation: () -> Void
    let onSetOrigin: (Stop) -> Void
    let onSetDestination: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedStation {
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

private struct GeoTrainMarker: View {
    let unit: GeoTrainUnit

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "tram.fill")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(unitTint, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 1.2)
                }

            Text(unit.line)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(unitTint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.1)
                }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityLabel("GeoTrain \(unit.line)")
    }

    private var unitTint: Color {
        if let isOnTime = unit.isOnTime {
            return isOnTime ? .teal : .orange
        }
        return .indigo
    }
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
