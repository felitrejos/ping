import CoreLocation
import MapKit
import SwiftUI

struct FGCMapView: View {
    @Environment(PingStore.self) private var store
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStation: Stop?
    @State private var originID: StopID?
    @State private var destinationID: StopID?
    @State private var isTMBOverlayEnabled = UserSettings.tmbEnabled()
    @State private var isFGCOverlayEnabled = UserSettings.fgcEnabled()
    @State private var lastCameraRegion: MKCoordinateRegion?
    @State private var visibleFGCStops: [Stop] = []
    @State private var visibleFGCDotStops: [Stop] = []
    @State private var fgcStopDisplayMode: StopDisplayMode = .hidden
    @State private var visibleTMBStops: [TMBStop] = []
    @State private var visibleTMBDotStops: [TMBStop] = []
    @State private var tmbStopDisplayMode: StopDisplayMode = .hidden
    @State private var selectedTMBStop: TMBStop?
    @State private var tmbArrivals: [TMBArrival] = []
    @State private var tmbLoadState: TMBLoadState = .idle
    @State private var fgcDepartures: [StationDeparture] = []
    @State private var fgcLoadState: FGCLoadState = .idle
    @State private var nearbyTMBStops: [TMBStop] = []
    @State private var closestFGCStations: [Stop] = []
    @State private var closestFGCStationIDs: Set<StopID> = []

    private let fgcInteractiveLatitudeDeltaThreshold: CLLocationDegrees = 0.05
    private let fgcDotLatitudeDeltaThreshold: CLLocationDegrees = 0.18
    private let tmbInteractiveLatitudeDeltaThreshold: CLLocationDegrees = 0.03
    private let tmbDotLatitudeDeltaThreshold: CLLocationDegrees = 0.09
    private let maxVisibleFGCInteractiveStops = 180
    private let maxVisibleFGCDotStops = 500
    private let maxVisibleTMBInteractiveStops = 120
    private let maxVisibleTMBDotStops = 400

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

    private var pinnedFGCStops: [Stop] {
        var seen = Set<StopID>()
        let anchors = [selectedStation] + closestFGCStations
        return anchors.compactMap { station in
            guard let station else {
                return nil
            }
            guard station.coordinate != nil, seen.insert(station.id).inserted else {
                return nil
            }
            return station
        }
    }

    private var pinnedTMBStops: [TMBStop] {
        var seen = Set<String>()
        let anchors = [selectedTMBStop].compactMap { $0 } + nearbyTMBStops
        return anchors.filter { stop in
            seen.insert(stop.id).inserted
        }
    }

    var body: some View {
        Map(position: $position) {
            if isFGCOverlayEnabled {
                if fgcStopDisplayMode == .dots {
                    ForEach(visibleFGCDotStops) { station in
                        if let coordinate = station.coordinate?.mapCoordinate {
                            Annotation(station.name, coordinate: coordinate) {
                                FGCStopDot()
                                    .allowsHitTesting(false)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }

                ForEach(visibleFGCStops) { station in
                    if let coordinate = station.coordinate?.mapCoordinate {
                        Annotation(station.name, coordinate: coordinate) {
                            Button {
                                clearSelectedTMBStop()
                                selectedStation = station
                                Task {
                                    await loadFGCDepartures(for: station)
                                }
                            } label: {
                                StationMarker(
                                    station: station,
                                    isNearby: closestFGCStationIDs.contains(station.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if isTMBOverlayEnabled {
                if tmbStopDisplayMode == .dots {
                    ForEach(visibleTMBDotStops) { stop in
                        Annotation(stop.name, coordinate: stop.coordinate.mapCoordinate) {
                            TMBStopDot()
                                .allowsHitTesting(false)
                        }
                        .annotationTitles(.hidden)
                    }
                }

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
                await refreshVisibleFGCStops(for: context.region)
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
                closestStations: closestFGCStations,
                closestBusStops: nearbyTMBStops,
                hasUserLocation: userCoordinate != nil,
                selectedStation: selectedStation,
                selectedBusStop: selectedTMBStop,
                stationDepartures: fgcDepartures,
                stationLoadState: fgcLoadState,
                busArrivals: tmbArrivals,
                busLoadState: tmbLoadState,
                onDismissStation: clearSelectedStation,
                onDismissBusStop: clearSelectedTMBStop,
                onRetryBusArrivals: {
                    guard let selectedTMBStop else {
                        return
                    }

                    Task {
                        await loadTMBArrivals(for: selectedTMBStop)
                    }
                },
                onRetryStationDepartures: {
                    guard let selectedStation else {
                        return
                    }

                    Task {
                        await loadFGCDepartures(for: selectedStation)
                    }
                }
            )
        }
        .task {
            await reloadMapData()
            isTMBOverlayEnabled = store.isTMBLayerPreferred
            isFGCOverlayEnabled = store.isFGCLayerPreferred
            if let lastCameraRegion {
                await refreshVisibleFGCStops(for: lastCameraRegion)
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
            await refreshClosestFGCStations()
            await refreshNearbyTMBStops()
            if let lastCameraRegion {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
        .refreshable {
            await store.refresh()
            await reloadMapData()
            if let lastCameraRegion {
                await refreshVisibleFGCStops(for: lastCameraRegion)
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
            await refreshClosestFGCStations()
            await refreshNearbyTMBStops()
            if let lastCameraRegion {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
        .onChange(of: store.availableStops) { _, _ in
            Task {
                await reloadMapData()
                if let lastCameraRegion {
                    await refreshVisibleFGCStops(for: lastCameraRegion)
                    await refreshVisibleTMBStops(for: lastCameraRegion)
                }
                await refreshClosestFGCStations()
                await refreshNearbyTMBStops()
                if let lastCameraRegion {
                    await refreshVisibleTMBStops(for: lastCameraRegion)
                }
            }
        }
        .onChange(of: store.userLocation) { _, _ in
            Task {
                await refreshClosestFGCStations()
                await refreshNearbyTMBStops()
                if let lastCameraRegion {
                    await refreshVisibleTMBStops(for: lastCameraRegion)
                }
            }
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
                visibleTMBDotStops = []
                tmbStopDisplayMode = .hidden
                return
            }

            guard let lastCameraRegion else {
                return
            }

            Task {
                await refreshVisibleTMBStops(for: lastCameraRegion)
            }
        }
        .onChange(of: isFGCOverlayEnabled) { _, isEnabled in
            store.setFGCEnabled(isEnabled)
            if !isEnabled {
                clearSelectedStation()
                visibleFGCStops = []
                visibleFGCDotStops = []
                fgcStopDisplayMode = .hidden
                return
            }

            guard let lastCameraRegion else {
                return
            }

            Task {
                await refreshVisibleFGCStops(for: lastCameraRegion)
            }
        }
    }

    @ViewBuilder
    private var mapOverlayControls: some View {
        VStack(spacing: 8) {
            fgcOverlayButton
            if store.hasTMBCredentials {
                tmbOverlayButton
            }
        }
    }

    @ViewBuilder
    private var fgcOverlayButton: some View {
        layerToggleButton(
            isOn: isFGCOverlayEnabled,
            systemImage: "tram.fill",
            onLabel: "Disable FGC station overlay",
            offLabel: "Enable FGC station overlay",
            hint: "Shows FGC train stations on the map"
        ) {
            isFGCOverlayEnabled.toggle()
        }
    }

    @ViewBuilder
    private var tmbOverlayButton: some View {
        layerToggleButton(
            isOn: isTMBOverlayEnabled,
            systemImage: "bus.fill",
            onLabel: "Disable TMB bus overlay",
            offLabel: "Enable TMB bus overlay",
            hint: "Shows nearby TMB bus stops on the map when zoomed in"
        ) {
            isTMBOverlayEnabled.toggle()
        }
    }

    @ViewBuilder
    private func layerToggleButton(
        isOn: Bool,
        systemImage: String,
        onLabel: String,
        offLabel: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)

                if !isOn {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 28, height: 2.5)
                        .rotationEffect(.degrees(-38))
                }
            }
            .foregroundStyle(isOn ? .primary : .secondary)
        }
        .accessibilityLabel(isOn ? onLabel : offLabel)
        .accessibilityHint(hint)
        .buttonStyle(.glass)
    }

    private func clearSelectedStation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStation = nil
            fgcDepartures = []
            fgcLoadState = .idle
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

    private func reloadMapData() async {
        originID = await store.selectedHomeStationID()
        destinationID = await store.selectedDestinationStationID()
        await refreshClosestFGCStations()
        updateCamera()
    }

    private func refreshClosestFGCStations() async {
        guard let userCoordinate else {
            closestFGCStations = []
            closestFGCStationIDs = []
            return
        }

        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let nearest = stationsWithCoordinates
            .sorted { first, second in
                first.distance(from: userLocation) < second.distance(from: userLocation)
            }
            .prefix(5)
            .map { $0 }

        closestFGCStations = nearest
        closestFGCStationIDs = Set(nearest.map(\.id))
    }

    private func refreshVisibleFGCStops(for region: MKCoordinateRegion) async {
        guard isFGCOverlayEnabled else {
            await MainActor.run {
                fgcStopDisplayMode = .hidden
                visibleFGCStops = []
                visibleFGCDotStops = []
            }
            return
        }

        let mode = stopDisplayMode(
            for: region.span.latitudeDelta,
            interactiveThreshold: fgcInteractiveLatitudeDeltaThreshold,
            dotsThreshold: fgcDotLatitudeDeltaThreshold
        )
        let regionBox = TransitBoundingBox(region: region)
        let pinnedStopsInRegion = pinnedFGCStops.filter { stop in
            guard let coordinate = stop.coordinate else {
                return false
            }
            return regionBox.contains(coordinate)
        }

        guard mode != .hidden else {
            await MainActor.run {
                fgcStopDisplayMode = .hidden
                visibleFGCStops = pinnedStopsInRegion
                visibleFGCDotStops = []
            }
            return
        }

        let center = TransitCoordinate(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let stops = await store.fgcStops(in: regionBox)

        if mode == .interactive {
            let sortedStops = stops.sorted { first, second in
                guard let firstCoordinate = first.coordinate, let secondCoordinate = second.coordinate else {
                    return false
                }
                return firstCoordinate.distanceSquared(to: center) < secondCoordinate.distanceSquared(to: center)
            }

            var interactiveStops = Array(sortedStops.prefix(maxVisibleFGCInteractiveStops))
            interactiveStops = mergedUnique(first: pinnedStopsInRegion, second: interactiveStops)

            await MainActor.run {
                fgcStopDisplayMode = .interactive
                visibleFGCStops = interactiveStops
                visibleFGCDotStops = []
            }
            return
        }

        let pinnedIDs = Set(pinnedStopsInRegion.map(\.id))
        let eligibleStops = stops.filter { !pinnedIDs.contains($0.id) }
        let sampledStops = sampledByGrid(
            eligibleStops,
            targetCount: maxVisibleFGCDotStops,
            region: region
        ) { stop in
            stop.coordinate ?? center
        }

        await MainActor.run {
            fgcStopDisplayMode = .dots
            visibleFGCStops = pinnedStopsInRegion
            visibleFGCDotStops = sampledStops
        }
    }

    private func refreshVisibleTMBStops(for region: MKCoordinateRegion) async {
        guard isTMBOverlayEnabled, store.isTMBEnabled else {
            await MainActor.run {
                tmbStopDisplayMode = .hidden
                visibleTMBStops = []
                visibleTMBDotStops = []
            }
            return
        }

        let mode = stopDisplayMode(
            for: region.span.latitudeDelta,
            interactiveThreshold: tmbInteractiveLatitudeDeltaThreshold,
            dotsThreshold: tmbDotLatitudeDeltaThreshold
        )
        let regionBox = TransitBoundingBox(region: region)
        let pinnedStopsInRegion = pinnedTMBStops.filter { stop in
            regionBox.contains(stop.coordinate)
        }
        let pinnedStopIDs = Set(pinnedStopsInRegion.map(\.id))

        guard mode != .hidden else {
            await MainActor.run {
                tmbStopDisplayMode = .hidden
                visibleTMBStops = pinnedStopsInRegion
                visibleTMBDotStops = []
                if let selectedTMBStop, !pinnedStopIDs.contains(selectedTMBStop.id) {
                    clearSelectedTMBStop()
                }
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

        if mode == .interactive {
            var interactiveStops = Array(sortedStops.prefix(maxVisibleTMBInteractiveStops))
            interactiveStops = mergedUnique(first: pinnedStopsInRegion, second: interactiveStops)
            if interactiveStops.count > maxVisibleTMBInteractiveStops {
                interactiveStops = Array(interactiveStops.prefix(maxVisibleTMBInteractiveStops))
            }

            await MainActor.run {
                tmbStopDisplayMode = .interactive
                visibleTMBStops = interactiveStops
                visibleTMBDotStops = []
                if let selectedTMBStop,
                   !interactiveStops.contains(where: { $0.id == selectedTMBStop.id }) {
                    clearSelectedTMBStop()
                }
            }
            return
        }

        let eligibleStops = sortedStops.filter { !pinnedStopIDs.contains($0.id) }
        let sampledStops = sampledByGrid(
            eligibleStops,
            targetCount: maxVisibleTMBDotStops,
            region: region
        ) { $0.coordinate }

        await MainActor.run {
            tmbStopDisplayMode = .dots
            visibleTMBStops = pinnedStopsInRegion
            visibleTMBDotStops = sampledStops
            if let selectedTMBStop, !pinnedStopIDs.contains(selectedTMBStop.id) {
                clearSelectedTMBStop()
            }
        }
    }

    private func stopDisplayMode(
        for latitudeDelta: CLLocationDegrees,
        interactiveThreshold: CLLocationDegrees,
        dotsThreshold: CLLocationDegrees
    ) -> StopDisplayMode {
        if latitudeDelta <= interactiveThreshold {
            return .interactive
        }
        if latitudeDelta <= dotsThreshold {
            return .dots
        }
        return .hidden
    }

    private func mergedUnique<Element: Identifiable>(
        first: [Element],
        second: [Element]
    ) -> [Element] where Element.ID: Hashable {
        var merged: [Element] = []
        var seen = Set<Element.ID>()

        for element in first where seen.insert(element.id).inserted {
            merged.append(element)
        }
        for element in second where seen.insert(element.id).inserted {
            merged.append(element)
        }
        return merged
    }

    private func sampledByGrid<Element>(
        _ elements: [Element],
        targetCount: Int,
        region: MKCoordinateRegion,
        coordinate: (Element) -> TransitCoordinate
    ) -> [Element] {
        guard elements.count > targetCount else {
            return elements
        }

        let center = TransitCoordinate(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let cellCountPerAxis = max(4, Int(sqrt(Double(targetCount))))
        let latitudeCellSize = max(region.span.latitudeDelta / Double(cellCountPerAxis), 0.0015)
        let longitudeCellSize = max(region.span.longitudeDelta / Double(cellCountPerAxis), 0.0015)
        let minimumLatitude = region.center.latitude - region.span.latitudeDelta / 2
        let minimumLongitude = region.center.longitude - region.span.longitudeDelta / 2

        var buckets: [GridSampleCell: Element] = [:]
        for element in elements {
            let itemCoordinate = coordinate(element)
            let latitudeIndex = Int(floor((itemCoordinate.latitude - minimumLatitude) / latitudeCellSize))
            let longitudeIndex = Int(floor((itemCoordinate.longitude - minimumLongitude) / longitudeCellSize))
            let key = GridSampleCell(latitudeIndex: latitudeIndex, longitudeIndex: longitudeIndex)

            if let existing = buckets[key] {
                let existingCoordinate = coordinate(existing)
                if itemCoordinate.distanceSquared(to: center) < existingCoordinate.distanceSquared(to: center) {
                    buckets[key] = element
                }
            } else {
                buckets[key] = element
            }
        }

        let sampled = buckets.values.sorted { first, second in
            coordinate(first).distanceSquared(to: center) < coordinate(second).distanceSquared(to: center)
        }
        return Array(sampled.prefix(targetCount))
    }

    private func refreshNearbyTMBStops() async {
        guard let userCoordinate else {
            await MainActor.run {
                nearbyTMBStops = []
            }
            return
        }

        guard store.hasTMBCredentials else {
            await MainActor.run {
                nearbyTMBStops = []
            }
            return
        }

        let nearbyBox = TMBBoundingBox(
            minLatitude: userCoordinate.latitude - 0.015,
            maxLatitude: userCoordinate.latitude + 0.015,
            minLongitude: userCoordinate.longitude - 0.02,
            maxLongitude: userCoordinate.longitude + 0.02
        )
        let center = TransitCoordinate(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let stops = await store.tmbStops(in: nearbyBox)
        let sortedStops = stops.sorted { first, second in
            first.coordinate.distanceSquared(to: center) < second.coordinate.distanceSquared(to: center)
        }

        await MainActor.run {
            nearbyTMBStops = Array(sortedStops.prefix(5))
        }
    }

    private func loadFGCDepartures(for station: Stop) async {
        fgcLoadState = .loading
        let result = await store.fgcDepartures(from: station.id)
        switch result {
        case let .success(departures):
            fgcDepartures = departures
            fgcLoadState = .idle
        case let .failure(error):
            fgcDepartures = []
            fgcLoadState = .error(error.displayMessage)
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

    private func updateCamera() {
        var coordinates: [CLLocationCoordinate2D] = []
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

}

private enum StopDisplayMode {
    case hidden
    case dots
    case interactive
}

private struct GridSampleCell: Hashable {
    let latitudeIndex: Int
    let longitudeIndex: Int
}

private struct StationMarker: View {
    let station: Stop
    let isNearby: Bool

    var body: some View {
        Image(systemName: "tram.fill")
            .font(.system(size: isNearby ? 14 : 12, weight: .bold))
            .foregroundStyle(isNearby ? .white : .blue)
            .frame(width: isNearby ? 32 : 24, height: isNearby ? 32 : 24)
            .background(isNearby ? .blue : .white, in: Circle())
            .overlay {
                Circle()
                    .stroke(.blue.opacity(isNearby ? 0.9 : 0.25), lineWidth: isNearby ? 3 : 1)
            }
            .background {
                if isNearby {
                    NearbyStationPulse()
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .accessibilityLabel(station.name)
    }
}

/// Expanding "live" ring behind the user's closest FGC station.
///
/// Drawn by a `TimelineView` rather than an `.animation(...).repeatForever(...)` driven by
/// `onAppear` state, because map annotations get created and destroyed as the user pans/zooms;
/// an `onAppear`-driven animation would reset its phase on every recycle and read as jittery.
/// The timeline-based phase is a pure function of wall-clock time, so recycled markers pick up
/// mid-cycle and stay in sync with each other.
private struct NearbyStationPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period: TimeInterval = 2.2

    var body: some View {
        if reduceMotion {
            // Reduce Motion: render a single static halo at mid-pulse so "this is your nearby
            // station" is still discoverable without the expanding ring. Same color, same alpha.
            Circle()
                .stroke(Color.blue.opacity(0.35), lineWidth: 2)
                .scaleEffect(1.4)
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let progress = (now.truncatingRemainder(dividingBy: period)) / period

                Circle()
                    .stroke(Color.blue.opacity(0.55), lineWidth: 2)
                    .scaleEffect(1.0 + 1.2 * progress)
                    .opacity(1.0 - progress)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct FGCStopDot: View {
    var body: some View {
        Circle()
            .fill(.blue.opacity(0.6))
            .frame(width: 6, height: 6)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 0.7)
            }
    }
}

private struct MapStatusPanel: View {
    let origin: Stop?
    let destination: Stop?
    let nextDeparture: LiveDeparture?
    let walkMinutes: Int
    let isUsingLiveLocation: Bool
    let closestStations: [Stop]
    let closestBusStops: [TMBStop]
    let hasUserLocation: Bool
    let selectedStation: Stop?
    let selectedBusStop: TMBStop?
    let stationDepartures: [StationDeparture]
    let stationLoadState: FGCLoadState
    let busArrivals: [TMBArrival]
    let busLoadState: TMBLoadState
    let onDismissStation: () -> Void
    let onDismissBusStop: () -> Void
    let onRetryBusArrivals: () -> Void
    let onRetryStationDepartures: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedBusStop {
                busStopSummary(for: selectedBusStop)
            } else if let selectedStation {
                stationSummary(for: selectedStation)
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
            Text("Route selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var nearbySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nearby stations", systemImage: "mappin.and.ellipse")
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("FGC: \(joinedStationNames(from: closestStations.map(\.name), fallback: "No nearby stations"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("TMB: \(joinedStationNames(from: closestBusStops.map(\.name), fallback: "No nearby stops"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text("Location is off, so nearby stations are unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func joinedStationNames(from names: [String], fallback: String) -> String {
        var seen = Set<String>()
        let uniqueNames = names.filter { seen.insert($0).inserted }
        if uniqueNames.isEmpty {
            return fallback
        }
        return uniqueNames.prefix(3).joined(separator: ", ")
    }

    private func stationSummary(for station: Stop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(station.name, systemImage: "tram.fill")
                .font(.headline)
                .lineLimit(2)
                .padding(.trailing, 48)

            switch stationLoadState {
            case .idle:
                if stationDepartures.isEmpty {
                    Text("No upcoming trains at this station.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(stationDepartures.prefix(5).enumerated()), id: \.offset) { _, departure in
                            HStack(spacing: 8) {
                                Text(departure.routeShortName)
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue.opacity(0.16), in: Capsule())

                                Text(departure.headsign)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Text(CountdownFormatting.compactMinutesText(minutes: departure.minutesUntilDeparture))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading departures…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case let .error(message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry", action: onRetryStationDepartures)
                        .buttonStyle(.bordered)
                }
            }
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
            HStack(spacing: 10) {
                Label(stop.name, systemImage: "bus.fill")
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.trailing, 48)

                Spacer()
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

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CountdownFormatting.compactMinutesText(minutes: arrival.minutesAway))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()

                                    if arrival.hasMeaningfulDelay {
                                        Text(arrival.delayMinutes > 0
                                            ? "+\(arrival.delayMinutes) min"
                                            : "\(arrival.delayMinutes) min")
                                            .font(.caption2.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(arrival.delayMinutes > 0 ? .orange : .green)
                                    }
                                }
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

private struct TMBStopDot: View {
    var body: some View {
        Circle()
            .fill(.orange.opacity(0.55))
            .frame(width: 5, height: 5)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.45), lineWidth: 0.6)
            }
    }
}

private enum TMBLoadState: Equatable {
    case idle
    case loading
    case error(String)
}

private enum FGCLoadState: Equatable {
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

private extension TransitBoundingBox {
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
