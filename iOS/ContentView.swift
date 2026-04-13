import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Home tab

struct ContentView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var tracker = CommuteTracker()
    @State private var selectedOriginID: StopID?
    @State private var selectedOriginName: String?
    @State private var selectedDestinationID: StopID?
    @State private var selectedDestinationName: String?
    @State private var activeFavoritePopoverStopID: StopID?
    @State private var activeStationPicker: StationPickerTarget?
    @State private var routeSearchCommitted = false
    @State private var isSearchingRoute = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    pingHeader
                    routeSection
                    quickSwitchSection
                    searchRoutesButton
                    serviceAlertsSection
                    statusBanner
                    calendarSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationDestination(isPresented: $routeSearchCommitted) {
                resultsScreen
            }
        }
        .sheet(item: $activeStationPicker) { target in
            NavigationStack {
                StationPickerSheet(
                    stops: store.availableStops,
                    title: target == .origin ? "Choose Origin" : "Choose Destination"
                ) { stop in
                    if target == .origin {
                        setPendingOrigin(stop.id)
                    } else {
                        setPendingDestination(stop.id)
                    }
                    activeStationPicker = nil
                }
            }
        }
        .refreshable { await store.refresh() }
        .onChange(of: store.nextDeparture) { _, dep in
            guard tracker.isTracking, let dep else { return }
            Task { await tracker.update(departure: dep, store: store) }
        }
        .onChange(of: store.availableStops) { _, stops in
            guard !stops.isEmpty else { return }
            Task { await prefillStationNames(from: stops) }
        }
        .onChange(of: store.lastUpdated) { _, _ in
            guard !store.availableStops.isEmpty else { return }
            Task { await prefillStationNames(from: store.availableStops) }
        }
        .task {
            if !store.availableStops.isEmpty {
                await prefillStationNames(from: store.availableStops)
            }
        }
    }

    private var resultsScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                serviceAlertsSection
                primaryCard
                upcomingDeparturesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pingHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            headerIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ping")
                    .font(.title3.weight(.semibold))
                Text("Never miss your train")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var headerIcon: some View {
        Image("PingHeaderLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white)
    }

    private var routeSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    stationPickerField(
                        title: "ORIGIN",
                        value: selectedOriginName ?? "Choose station"
                    ) {
                        activeStationPicker = .origin
                    }

                    stationPickerField(
                        title: "DESTINATION",
                        value: selectedDestinationName ?? "Choose station",
                        topPadding: 14
                    ) {
                        activeStationPicker = .destination
                    }
                }

                Button {
                    guard hasPendingDefaultRoute else {
                        return
                    }
                    swapPendingRoute()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.headline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .opacity(hasPendingDefaultRoute ? 1 : 0.45)
                .disabled(!hasPendingDefaultRoute)
                .accessibilityLabel("Swap origin and destination")
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var quickSwitchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Favorites")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !store.favoriteStations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.favoriteStations) { stop in
                            Button {
                                activeFavoritePopoverStopID = stop.id
                            } label: {
                                Text(stop.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .popover(
                                isPresented: favoritePopoverBinding(for: stop.id),
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .bottom
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button {
                                        setPendingOrigin(stop.id)
                                        activeFavoritePopoverStopID = nil
                                    } label: {
                                        Text("Set as origin")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                                    .controlSize(.large)

                                    Button {
                                        setPendingDestination(stop.id)
                                        activeFavoritePopoverStopID = nil
                                    } label: {
                                        Text("Set as destination")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.green)
                                    .controlSize(.large)
                                }
                                .frame(minWidth: 180)
                                .padding()
                                .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "star")
                        .foregroundStyle(.secondary)
                    Text("Add favorite stations in Settings for quick route switching.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, -2)
    }

    private var searchRoutesButton: some View {
        VStack(spacing: 10) {
            Button {
                if !store.isLocationAccessGranted {
                    if store.isLocationAccessDenied {
                        openAppSettings()
                    } else {
                        store.requestLocationAccess()
                    }
                    return
                }
                Task { await searchRoutes() }
            } label: {
                HStack {
                    if isSearchingRoute {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(searchRoutesButtonTitle)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isLocationAccessGranted ? .blue : .orange)
            .controlSize(.large)
            .disabled(isSearchingRoute || (store.isLocationAccessGranted && !hasPendingDefaultRoute))
        }
    }

    private var searchRoutesButtonTitle: String {
        if isSearchingRoute {
            return "Searching..."
        }
        if !store.isLocationAccessGranted {
            return store.isLocationAccessDenied ? "Open settings to enable location" : "Enable location to search routes"
        }
        return "Search routes"
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private func favoritePopoverBinding(for stopID: StopID) -> Binding<Bool> {
        Binding(
            get: { activeFavoritePopoverStopID == stopID },
            set: { isPresented in
                activeFavoritePopoverStopID = isPresented ? stopID : nil
            }
        )
    }

    private var hasPendingDefaultRoute: Bool {
        selectedOriginID != nil && selectedDestinationID != nil
    }

    private func setPendingOrigin(_ stopID: StopID) {
        selectedOriginID = stopID
        selectedOriginName = stationName(for: stopID)
    }

    private func setPendingDestination(_ stopID: StopID) {
        selectedDestinationID = stopID
        selectedDestinationName = stationName(for: stopID)
    }

    private func stationName(for stopID: StopID) -> String? {
        store.availableStops.first(where: { $0.id == stopID })?.name
    }

    private func swapPendingRoute() {
        guard let originID = selectedOriginID, let destinationID = selectedDestinationID else {
            return
        }

        let originName = selectedOriginName
        selectedOriginID = destinationID
        selectedOriginName = selectedDestinationName
        selectedDestinationID = originID
        selectedDestinationName = originName
    }

    private func searchRoutes() async {
        guard let originID = selectedOriginID, let destinationID = selectedDestinationID else {
            return
        }

        isSearchingRoute = true
        defer { isSearchingRoute = false }

        await store.setRoute(origin: originID, destination: destinationID)
        routeSearchCommitted = true
    }

    private func stationPickerField(
        title: String,
        value: String,
        topPadding: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.3)
                .padding(.top, topPadding)
                .padding(.bottom, 4)

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.title3)
                        .foregroundStyle(selectedLabelColor(for: value))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func selectedLabelColor(for value: String) -> Color {
        value == "Choose station" ? .secondary : .primary
    }

    private func prefillStationNames(from stops: [Stop]) async {
        let originID = await store.selectedHomeStationID()
        let destID = await store.selectedDestinationStationID()
        selectedOriginID = originID
        selectedDestinationID = destID
        selectedOriginName = originID.flatMap { id in stops.first(where: { $0.id == id })?.name }
        selectedDestinationName = destID.flatMap { id in stops.first(where: { $0.id == id })?.name }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let msg = store.lastErrorMessage {
            NoticeCard(
                title: "Could not refresh",
                message: msg,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    @ViewBuilder
    private var serviceAlertsSection: some View {
        let alerts = actionableServiceAlerts
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let primaryAlert = alerts.max(by: { severityRank($0.severity) < severityRank($1.severity) }) {
                    NoticeCard(
                        title: primaryAlert.title,
                        message: primaryAlert.details,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: severityColor(primaryAlert.severity)
                    )
                }

                if !lineStatusRows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lineStatusRows) { row in
                                HStack(spacing: 6) {
                                    Text(row.line)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 20)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    Text(severityLabel(row.severity))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(severityColor(row.severity))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                        }
                    }
                }

                if let lastUpdated = store.serviceAlertsLastUpdated {
                    AlertsFreshnessCaption(lastUpdated: lastUpdated)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var lineStatusRows: [LineStatusRow] {
        var severityByLine: [String: ServiceAlertSeverity] = [:]
        for alert in actionableServiceAlerts {
            for line in alert.affectedLines {
                let current = severityByLine[line]
                if let current {
                    if severityRank(alert.severity) > severityRank(current) {
                        severityByLine[line] = alert.severity
                    }
                } else {
                    severityByLine[line] = alert.severity
                }
            }
        }

        return severityByLine
            .map { LineStatusRow(line: $0.key, severity: $0.value) }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
    }

    private var actionableServiceAlerts: [ServiceAlert] {
        store.activeServiceAlerts.filter { $0.severity != .info }
    }

    private func severityRank(_ severity: ServiceAlertSeverity) -> Int {
        switch severity {
        case .info:
            0
        case .minor:
            1
        case .major:
            2
        case .closure:
            3
        }
    }

    private func severityColor(_ severity: ServiceAlertSeverity) -> Color {
        switch severity {
        case .info:
            .blue
        case .minor:
            .yellow
        case .major:
            .orange
        case .closure:
            .red
        }
    }

    private func severityLabel(_ severity: ServiceAlertSeverity) -> String {
        switch severity {
        case .info:
            "Info"
        case .minor:
            "Minor"
        case .major:
            "Major"
        case .closure:
            "Closure"
        }
    }

    @ViewBuilder
    private var primaryCard: some View {
        if routeSearchCommitted, store.hasConfiguredDefaultRoute, let dep = store.nextDeparture {
            TrainHeroCard(
                departure: dep,
                isTracking: tracker.isTracking,
                onStartTracking: { Task { await tracker.start(departure: dep, store: store) } },
                onStopTracking: { Task { await tracker.stop() } }
            )
        } else if routeSearchCommitted, store.hasConfiguredDefaultRoute {
            NoTrainsCard()
        }
    }

    @ViewBuilder
    private var upcomingDeparturesSection: some View {
        let departures = upcomingDepartureRows
        if routeSearchCommitted, store.hasConfiguredDefaultRoute, !departures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Upcoming departures")
                        .font(.headline)
                    Spacer()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(departures) { departure in
                            departureBoardRow(departure)
                            if departure.id != departures.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func departureBoardRow(_ departure: LiveDeparture) -> some View {
        let routeCode = departure.trainLabel.split(separator: " ").first.map(String.init) ?? "FGC"

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(routeCode)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 20)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 6) {
                    Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    Text("→")
                    Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Leave in")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                CountdownText(
                    targetDate: departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-store.walkingMinutes * 60)),
                    mode: .board
                )
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if departure.isDelayed {
                    Text("+\(departure.delayMinutes) min")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func commuteRow(_ plan: CommutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.calendarEvent.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let calendarRouteDetail = CommutePresentation.calendarRouteDetail(
                        for: plan,
                        availableStops: store.availableStops
                    ) {
                        Text(calendarRouteDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
                Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                applyCommutePlan(plan)
            } label: {
                Label("Use this route", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar")
                .font(.headline)

            if !store.calendarAuthorization.isAuthorized {
                calendarAccessCard
            } else if let plan = nextCalendarCommute {
                commuteRow(plan)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No upcoming calendar commutes")
                            .font(.subheadline.weight(.semibold))
                        Text("Add events with a location to see route suggestions here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var calendarAccessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable calendar access")
                        .font(.subheadline.weight(.semibold))
                    Text("Allow calendar access to get commute suggestions from your upcoming events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if store.calendarAuthorization == .denied || store.calendarAuthorization == .restricted {
                    openAppSettings()
                } else {
                    Task { await store.requestCalendarAccess() }
                }
            } label: {
                Text(store.calendarAuthorization == .denied || store.calendarAuthorization == .restricted ? "Open settings" : "Enable calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func applyCommutePlan(_ plan: CommutePlan) {
        setPendingOrigin(plan.originStationID)
        setPendingDestination(plan.destinationStationID)
    }

    private var nextCalendarCommute: CommutePlan? {
        store.commutePlans.first { !isCurrentRoutePlan($0) }
    }

    private var upcomingDepartureRows: [LiveDeparture] {
        guard let nextDeparture = store.nextDeparture else {
            return store.upcomingDepartures
        }

        return store.upcomingDepartures.filter { $0.id != nextDeparture.id }
    }

    private func isCurrentRoutePlan(_ plan: CommutePlan) -> Bool {
        guard let currentOrigin = store.homeStationID, let currentDestination = store.destinationStationID else {
            return false
        }

        return plan.originStationID == currentOrigin && plan.destinationStationID == currentDestination
    }

}

// MARK: - Commute tracker (manages Live Activity)

@MainActor
@Observable
final class CommuteTracker {
    var isTracking = false

    #if canImport(ActivityKit)
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<PingActivityAttributes>?
    #endif

    func start(departure: LiveDeparture, store: PingStore) async {
        isTracking = true
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let destName = store.availableStops.first(where: { $0.id == departure.destinationStopID })?.name
            ?? departure.destinationStopID
        let walkMin = store.walkingMinutes
        let rideMin = max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
        let attrs = PingActivityAttributes(
            destinationName: destName,
            lineName: store.selectedLine
        )
        let state = PingActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            walkMinutes: walkMin,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime
        )
        activity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        #endif
    }

    func update(departure: LiveDeparture, store: PingStore) async {
        guard isTracking else { return }
        #if canImport(ActivityKit)
        let walkMin = store.walkingMinutes
        let rideMin = max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
        let state = PingActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            walkMinutes: walkMin,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime
        )
        await activity?.update(.init(state: state, staleDate: nil))
        #endif
    }

    func stop() async {
        isTracking = false
        #if canImport(ActivityKit)
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        #endif
    }
}

// MARK: - Train hero card

private struct TrainHeroCard: View {
    let departure: LiveDeparture
    let isTracking: Bool
    let onStartTracking: () -> Void
    let onStopTracking: () -> Void
    @Environment(PingStore.self) private var store

    private var walkMin: Int { store.walkingMinutes }
    private var rideMin: Int {
        max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
    }
    private var routeCode: String {
        departure.trainLabel.split(separator: " ").first.map(String.init) ?? store.selectedLine
    }
    private var leaveByDate: Date {
        departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-walkMin * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveActivityRow
            Divider().padding(.horizontal, 16)
            departureTimingHeader
            heroCountdown
            timelineSection
            if departure.isDelayed {
                Divider().padding(.horizontal, 16)
                statusRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var departureTimingHeader: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 5) {
                    Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.callout.weight(.semibold))

                Text(routeCode)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 18)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var heroCountdown: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Leave in")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HeroCountdownValue(targetDate: leaveByDate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var timelineSection: some View {
        let total = walkMin + rideMin
        let walkFraction = CGFloat(walkMin) / CGFloat(total)

        return VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.55))
                        .frame(width: max(24, (geo.size.width - 2) * walkFraction))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                }
            }
            .frame(height: 8)

            HStack {
                Label("\(walkMin) min walk", systemImage: store.isUsingLiveLocation ? "location.fill" : "figure.walk")
                    .foregroundStyle(.blue)
                Spacer()
                Label("\(rideMin) min ride", systemImage: "tram.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            Text("Delayed · \(departure.statusText)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var liveActivityRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isTracking ? "livephoto" : "sparkles")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 18)

            Text(isTracking ? "Following trip" : "Live Activity")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            if isTracking {
                Button(action: onStopTracking) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button(action: onStartTracking) {
                    Label("Follow trip", systemImage: "livephoto")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Supporting views

private struct CountdownText: View {
    enum Mode {
        case hero
        case board
    }

    let targetDate: Date
    let mode: Mode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            Text(formattedCountdown(remainingSeconds: remainingSeconds))
        }
    }

    private func formattedCountdown(remainingSeconds: Int) -> String {
        switch mode {
        case .hero:
            let parts = CountdownFormatting.heroParts(remainingSeconds: remainingSeconds)
            return parts.plainText
        case .board:
            return CountdownFormatting.boardText(remainingSeconds: remainingSeconds)
        }
    }
}

private struct HeroCountdownValue: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            let parts = CountdownFormatting.heroParts(remainingSeconds: remainingSeconds)

            if parts.isLongForm {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(parts.trailingValue ?? "")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text(parts.trailingUnit ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct NoTrainsCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No upcoming trains")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AlertsFreshnessCaption: View {
    let lastUpdated: Date
    private let staleThreshold: TimeInterval = 15 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let isStale = timeline.date.timeIntervalSince(lastUpdated) >= staleThreshold

            HStack(spacing: 0) {
                Text("Updated ")
                Text(lastUpdated, style: .relative)
                if isStale {
                    Text(" · may be outdated")
                }
            }
            .font(.caption2)
            .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}

private struct LineStatusRow: Identifiable {
    let line: String
    let severity: ServiceAlertSeverity

    var id: String {
        line
    }
}

private enum StationPickerTarget: String, Identifiable {
    case origin
    case destination

    var id: String {
        rawValue
    }
}

private struct StationPickerSheet: View {
    let stops: [Stop]
    let title: String
    let onSelect: (Stop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredStops: [Stop] {
        stops
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section("Stations") {
                ForEach(filteredStops) { stop in
                    Button {
                        onSelect(stop)
                        dismiss()
                    } label: {
                        Text(stop.name)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search station")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

private struct NoticeCard: View {
    let title: String
    let message: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
