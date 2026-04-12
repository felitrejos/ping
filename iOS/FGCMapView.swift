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

    private var stationsWithCoordinates: [Stop] {
        store.availableStops.filter { $0.coordinate != nil }
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

    private var railPolyline: MKPolyline? {
        let coordinates = routeStops.compactMap { $0.coordinate?.mapCoordinate }
        guard coordinates.count >= 2 else {
            return nil
        }

        return MKPolyline(coordinates: coordinates, count: coordinates.count)
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

            if let railPolyline {
                MapPolyline(railPolyline)
                    .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            ForEach(stationsWithCoordinates) { station in
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

            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
            MapScaleView()
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
                onDismissStation: clearSelectedStation,
                onClearRoute: {
                    clearSelectedStation()
                    Task {
                        await store.clearDefaultRoute()
                        await reloadMapData()
                    }
                },
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
                onRequestLocation: {
                    store.requestLocationAccess()
                }
            )
        }
        .task {
            await reloadMapData()
        }
        .refreshable {
            await store.refresh()
            await reloadMapData()
        }
        .onChange(of: store.availableStops) { _, _ in
            Task { await reloadMapData() }
        }
        .onChange(of: store.userLocation) { _, _ in
            Task { await updateWalkingRoute() }
        }
        .onChange(of: store.nextDeparture) { _, _ in
            Task { await updateWalkingRoute() }
        }
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
        case .origin:
            .blue
        case .destination:
            .green
        case .route:
            .green
        case .nearby:
            .white
        }
    }

    var symbol: String {
        switch self {
        case .origin:
            "target"
        case .destination:
            "flag.checkered"
        case .route:
            "tram.fill"
        case .nearby:
            "tram"
        }
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
    let onClearRoute: () -> Void
    let onSetOrigin: (Stop) -> Void
    let onSetDestination: (Stop) -> Void
    let onRequestLocation: () -> Void

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
                clearRouteButton
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

                clearRouteButton
            }
            Text("\(max(routeStops.count - 1, 0)) station hops from GTFS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var clearRouteButton: some View {
        Button(role: .destructive, action: onClearRoute) {
            Label("Clear route", systemImage: "xmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
                } else {
                    Button("Find nearby", action: onRequestLocation)
                        .font(.subheadline.weight(.semibold))
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
        if #available(iOS 26.0, *) {
            if isPrimary {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        } else {
            if isPrimary {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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
