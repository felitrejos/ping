import Combine
import CoreLocation
import SwiftUI
import UserNotifications
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Home tab

struct ContentView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var isServiceAlertsSheetPresented = false
    /// Wall clock used to re-evaluate `timeOfDaySuggestion`. Ticking at a minute cadence
    /// is plenty — the suggestion only crosses morning/evening thresholds on the hour.
    @State private var suggestionClock = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    pingHeader
                    serviceStatusPill
                    routeSection
                    timeOfDaySuggestion
                    quickSwitchSection
                    savedRoutesSection
                    searchRoutesButton
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
                    title: target == .origin ? "Choose Origin" : "Choose Destination",
                    counterpartStopID: target == .origin ? selectedDestinationID : selectedOriginID,
                    excludedStopIDs: Set([target == .origin ? selectedDestinationID : selectedOriginID].compactMap { $0 })
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
        .onChange(of: store.nextDeparture) { _, _ in
            Task { await tracker.syncWithStore(store) }
        }
        .onChange(of: store.upcomingDepartures) { _, _ in
            Task { await tracker.syncWithStore(store) }
        }
        .onChange(of: store.availableStops) { _, stops in
            guard !stops.isEmpty else { return }
            Task { await prefillStationNames(from: stops) }
        }
        .onChange(of: store.lastUpdated) { _, _ in
            Task { await tracker.syncWithStore(store) }
            guard !store.availableStops.isEmpty else { return }
            Task { await prefillStationNames(from: store.availableStops) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await tracker.syncWithStore(store) }
            // Refresh the suggestion clock on foreground so a user who keeps the app open
            // across morning → evening sees the right card without waiting for the next tick.
            suggestionClock = Date()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            suggestionClock = date
        }
        .task {
            await tracker.syncWithStore(store)
            if !store.availableStops.isEmpty {
                await prefillStationNames(from: store.availableStops)
            }
        }
        .task(id: tracker.isTracking) {
            // Drive phase transitions (leave-now, <2 min, missed) while a trip is locked.
            // Store refreshes can be minutes apart so we tick ourselves here.
            guard tracker.isTracking else { return }
            while !Task.isCancelled, tracker.isTracking {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await tracker.syncWithStore(store)
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
            .foregroundStyle(.primary)
    }

    /// Single grouped card for the origin/destination picker.
    ///
    /// Layout borrows from Apple Maps: two rows separated by a hairline, with a circular swap
    /// affordance floating over the divider on the trailing edge. The card-level background
    /// replaces the two per-field backgrounds we used to stack, so the whole thing reads as one
    /// primary search control rather than three loose elements.
    private var routeSection: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                stationPickerRow(
                    title: "ORIGIN",
                    value: selectedOriginName ?? "Choose station"
                ) {
                    activeStationPicker = .origin
                }

                Divider()
                    .padding(.leading, 16)

                stationPickerRow(
                    title: "DESTINATION",
                    value: selectedDestinationName ?? "Choose station"
                ) {
                    activeStationPicker = .destination
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            swapRouteButton
                .padding(.trailing, 10)
        }
    }

    private var swapRouteButton: some View {
        Button {
            guard hasPendingDefaultRoute else { return }
            swapPendingRoute()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(Color(.tertiarySystemBackground))
                        .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
                }
        }
        .buttonStyle(.plain)
        .opacity(hasPendingDefaultRoute ? 1 : 0.4)
        .disabled(!hasPendingDefaultRoute)
        .accessibilityLabel("Swap origin and destination")
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

    // MARK: - Saved routes

    /// One-tap origin/destination chips.
    ///
    /// Tapping a chip applies the route and immediately runs a search — that's the common
    /// intent (switching between Home → Work and Work → Home), so we skip the intermediate
    /// popover. Long-press surfaces a destructive "Remove" action via `contextMenu`. The
    /// trailing `+` in the header saves the currently-pending route when it's configured and
    /// not already saved.
    @ViewBuilder
    private var savedRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Saved routes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    guard let origin = selectedOriginID,
                          let destination = selectedDestinationID else { return }
                    store.addSavedRoute(origin: origin, destination: destination)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canSaveCurrentRoute ? Color.blue : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSaveCurrentRoute)
                .accessibilityLabel("Save current route")
            }

            if !store.savedRoutes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.savedRoutes) { route in
                            savedRouteChip(route)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .foregroundStyle(.secondary)
                    Text("Tap the + above to save this route for one-tap switching later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func savedRouteChip(_ route: SavedRoute) -> some View {
        let originName = stationName(for: route.originID) ?? route.originID
        let destName = stationName(for: route.destinationID) ?? route.destinationID

        Button {
            applySavedRoute(route)
        } label: {
            HStack(spacing: 6) {
                Text(originName)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(destName)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.removeSavedRoute(route)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityLabel("Apply route \(originName) to \(destName)")
    }

    private var canSaveCurrentRoute: Bool {
        guard let origin = selectedOriginID,
              let destination = selectedDestinationID,
              origin != destination else {
            return false
        }
        return !store.isRouteSaved(origin: origin, destination: destination)
    }

    private func applySavedRoute(_ route: SavedRoute) {
        // Fill the pending origin/destination only. The user still has to hit "Search routes"
        // to commit — same mental model as tapping a favorite station, and it avoids surprising
        // navigation when the user is mid-glance.
        setPendingOrigin(route.originID)
        setPendingDestination(route.destinationID)
    }

    // MARK: - Service status pill

    /// Ambient one-line FGC health summary under the header.
    ///
    /// Reads from `store.activeServiceAlerts` — no new network calls. Info alerts are
    /// excluded (they're announcements, not disruptions), so the pill only goes tappable
    /// when there's at least one actionable alert. Otherwise it's a static "all running"
    /// reassurance.
    private var serviceStatusPill: some View {
        let actionable = actionableServiceAlerts.count
        let hasActionable = actionable > 0

        let tint: Color = hasActionable ? .orange : .green
        let systemImage = hasActionable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let label = hasActionable
            ? "FGC · \(actionable) alert\(actionable == 1 ? "" : "s")"
            : "FGC · All lines running"

        let pillBody = HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if hasActionable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint.opacity(0.6))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())

        return Group {
            if hasActionable {
                Button {
                    isServiceAlertsSheetPresented = true
                } label: {
                    pillBody
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label). Tap to see details.")
                .accessibilityAddTraits(.isButton)
            } else {
                pillBody
                    .accessibilityElement(children: .combine)
            }
        }
        .sheet(isPresented: $isServiceAlertsSheetPresented) {
            ServiceAlertsSheet(alerts: store.activeServiceAlerts)
        }
    }

    // MARK: - Time-of-day suggestion

    /// A contextual one-tap nudge based on the wall clock + configured home station.
    ///
    /// Two triggers:
    ///   - Morning (05:00–11:59) + pending origin is not `homeStationID` + home is known
    ///     → `"Start from home?"` sets pending origin to home.
    ///   - Evening (17:00–23:59) + pending origin is `homeStationID` + pending destination
    ///     is set and is not home → `"Heading home?"` swaps origin and destination.
    ///
    /// Returns `EmptyView` otherwise; driven by a 60 s `TimelineView` tick so the card
    /// appears/disappears as the hour rolls without a full scene refresh.
    @ViewBuilder
    private var timeOfDaySuggestion: some View {
        // Using a plain `if let` (instead of wrapping in a TimelineView) is deliberate:
        // SwiftUI's VStack collapses spacing around a nil branch, but treats a TimelineView
        // containing EmptyView as a real zero-size view and still applies full spacing. So
        // when there's no suggestion we render literally nothing, and `suggestionClock`
        // drives recomputation via .onReceive in the root body.
        if let suggestion = resolveTimeOfDaySuggestion(at: suggestionClock) {
            timeOfDayCard(suggestion)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private enum TimeOfDaySuggestion: Equatable {
        case startFromHome(homeID: StopID, homeName: String)
        case reverseToHome

        var title: String {
            switch self {
            case .startFromHome: "Start from home?"
            case .reverseToHome: "Heading home?"
            }
        }

        var subtitle: String {
            switch self {
            case .startFromHome(_, let homeName): "Set \(homeName) as origin."
            case .reverseToHome: "Reverse today's route."
            }
        }

        var actionLabel: String {
            switch self {
            case .startFromHome: "Use home"
            case .reverseToHome: "Reverse"
            }
        }

        var systemImage: String {
            switch self {
            case .startFromHome: "house.fill"
            case .reverseToHome: "arrow.uturn.backward"
            }
        }
    }

    private func resolveTimeOfDaySuggestion(at date: Date) -> TimeOfDaySuggestion? {
        let hour = Calendar.current.component(.hour, from: date)
        guard let homeID = store.homeStationID else { return nil }

        // Morning path — user probably wants to start from home.
        if (5...11).contains(hour),
           selectedOriginID != homeID,
           let homeName = stationName(for: homeID) {
            return .startFromHome(homeID: homeID, homeName: homeName)
        }

        // Evening path — user probably wants to head back home. Requires a fully-configured
        // outbound route so the "reverse" action has something to operate on.
        if (17...23).contains(hour),
           selectedOriginID == homeID,
           let destinationID = selectedDestinationID,
           destinationID != homeID {
            return .reverseToHome
        }

        return nil
    }

    private func timeOfDayCard(_ suggestion: TimeOfDaySuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                Text(suggestion.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                applyTimeOfDaySuggestion(suggestion)
            } label: {
                Text(suggestion.actionLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func applyTimeOfDaySuggestion(_ suggestion: TimeOfDaySuggestion) {
        switch suggestion {
        case .startFromHome(let homeID, _):
            setPendingOrigin(homeID)
        case .reverseToHome:
            swapPendingRoute()
        }
    }

    private var searchRoutesButton: some View {
        VStack(spacing: 6) {
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

            // "Allow Once" on the iOS prompt grants location only for that session, so the user
            // sees this CTA again on every launch. Nudge toward "While Using the App" (persistent)
            // before they see the system prompt. Only shown when undetermined — not when denied,
            // since that path goes to Settings.
            if !store.isLocationAccessGranted && !store.isLocationAccessDenied {
                Text("Tip: pick \u{201C}While Using the App\u{201D} to avoid re-enabling every launch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
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
#if canImport(AppIntents)
        await PingIntentSupport.donateNextDepartureIntent()
#endif
        routeSearchCommitted = true
    }

    /// A single row inside the unified route card — no background, no trailing icon.
    ///
    /// The parent `routeSection` provides the card background and the floating swap button, so
    /// this row only needs to render the label + value. Right padding reserves space so that
    /// long station names don't run under the swap button overlay.
    private func stationPickerRow(
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3)
                        .foregroundStyle(selectedLabelColor(for: value))
                        .lineLimit(1)
                }
                Spacer(minLength: 56)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectedLabelColor(for value: String) -> Color {
        value == "Choose station" ? .secondary : .primary
    }

    private func prefillStationNames(from stops: [Stop]) async {
        let persistedOriginID = await store.selectedHomeStationID()
        let persistedDestinationID = await store.selectedDestinationStationID()

        if let persistedOriginID {
            selectedOriginID = persistedOriginID
            selectedOriginName = stops.first(where: { $0.id == persistedOriginID })?.name
        } else if selectedOriginID == nil {
            selectedOriginName = nil
        }

        if let persistedDestinationID {
            selectedDestinationID = persistedDestinationID
            selectedDestinationName = stops.first(where: { $0.id == persistedDestinationID })?.name
        } else if selectedDestinationID == nil {
            selectedDestinationName = nil
        }
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
                if let primaryAlert = ServiceAlertPresentation.primaryAlert(from: alerts) {
                    NoticeCard(
                        title: primaryAlert.title,
                        message: primaryAlert.details,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: ServiceAlertPresentation.color(for: primaryAlert.severity)
                    )
                }

                let rows = ServiceAlertPresentation.lineStatusRows(from: alerts)
                if !rows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(rows) { row in
                                HStack(spacing: 6) {
                                    Text(row.line)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 20)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    Text(ServiceAlertPresentation.label(for: row.severity))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ServiceAlertPresentation.color(for: row.severity))
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

    private var actionableServiceAlerts: [ServiceAlert] {
        ServiceAlertPresentation.actionableAlerts(from: store.activeServiceAlerts)
    }

    @ViewBuilder
    private var primaryCard: some View {
        if routeSearchCommitted, store.hasConfiguredDefaultRoute {
            if let displayed = heroDeparture {
                TrainHeroCard(
                    tracker: tracker,
                    departure: displayed,
                    onStartTracking: {
                        Task { await tracker.start(departure: displayed, store: store) }
                    },
                    onStopTracking: { Task { await tracker.stop() } },
                    onSwitchToNextTrain: { Task { await tracker.switchToNextTrain(store: store) } }
                )
                .modifier(TrackingHapticsModifier(tracker: tracker))
                .modifier(LeaveNowBumpModifier(tracker: tracker))
            } else {
                NoTrainsCard()
            }
        }
    }

    /// Departure shown at the top. In Planning mode this is the auto-rolling next catchable
    /// train. In TrackingLocked mode this is the locked trip — even when it's already missed.
    private var heroDeparture: LiveDeparture? {
        tracker.trackedDeparture ?? store.nextDeparture
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
        let isTrackingLocked = tracker.isTrackingLocked
        let followButtonLabel = isTrackingLocked ? "Switch" : "Follow"
        let followButtonIcon = isTrackingLocked ? "arrow.triangle.2.circlepath" : "livephoto"

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
                    targetDate: departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-store.walkingMinutes * 60))
                )
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if departure.isDelayed {
                    Text("+\(departure.delayMinutes) min")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Button {
                Task { await tracker.start(departure: departure, store: store) }
            } label: {
                Label(followButtonLabel, systemImage: followButtonIcon)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(isTrackingLocked ? .orange : .blue)
            .accessibilityLabel(isTrackingLocked ? "Switch to this train" : "Follow this trip")
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
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("Nothing upcoming.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
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
        let heroTripID = heroDeparture?.tripID
        return store.upcomingDepartures.filter { departure in
            departure.id != store.nextDeparture?.id && departure.tripID != heroTripID
        }
    }

    private func isCurrentRoutePlan(_ plan: CommutePlan) -> Bool {
        guard let currentOrigin = store.homeStationID, let currentDestination = store.destinationStationID else {
            return false
        }

        return plan.originStationID == currentOrigin && plan.destinationStationID == currentDestination
    }

}

// MARK: - Commute tracker (manages Live Activity)

/// Centralised state machine for commute tracking.
///
/// Two modes:
///   * **Planning** — `trackedDeparture == nil`. The hero auto-rolls to the next catchable train.
///   * **TrackingLocked** — user tapped *Follow trip*, pinning a specific `tripID`.
///     We keep rendering that trip even if the store drops it from the upcoming list, and we
///     recompute a `phase` (`tracking`, `likelyMissed`, `missed`) so the UI can react.
@MainActor
@Observable
final class CommuteTracker {
    private static let persistedTripIDKey = "ping.trackedTripID"

    /// `true` while a Live Activity is running. Also implies `trackedDeparture != nil`.
    var isTracking = false
    /// Snapshot of the locked trip, refreshed from the store whenever possible.
    var trackedDeparture: LiveDeparture?
    /// Phase derived from the tracked trip + latest walking ETA.
    var phase: TrackingPhase = .planning
    /// Signed slack between now and *leave-by*. Negative when the user is already behind.
    var bufferSeconds: Int = 0
    /// Minutes until the tracked train actually departs, recomputed from wall-clock each tick.
    /// `nil` while planning (no trip locked).
    var minutesUntilDeparture: Int?

    /// Cached walking ETA; private because it's an internal derivation from the store, not
    /// something callers need to reach into.
    @ObservationIgnored private var walkMinutes: Int = 0

    #if canImport(ActivityKit)
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<PingActivityAttributes>?
    #endif

    // Transition detection so Live Activity alerts only fire when crossing a threshold,
    // never when restoring a persisted trip or on every refresh.
    @ObservationIgnored private var hasSeededAlertState = false
    @ObservationIgnored private var lastAlertPhase: TrackingPhase = .planning
    @ObservationIgnored private var lastAlertMinutesBucket: Int = .max
    @ObservationIgnored private var lastAlertBufferBucket: Int = .max

    private enum AlertTrigger {
        case leaveNow, twoMinutes, missed
    }

    var trackedTripID: String? { trackedDeparture?.tripID }
    var isTrackingLocked: Bool { trackedDeparture != nil }

    func syncWithSystemActivityState() async {
        #if canImport(ActivityKit)
        let activeActivities = Activity<PingActivityAttributes>.activities

        if let activity, activeActivities.contains(where: { $0.id == activity.id }) {
            isTracking = true
            return
        }

        if let adopted = activeActivities.first {
            activity = adopted
            isTracking = true
            return
        }

        activity = nil
        #endif
        isTracking = false
    }

    /// Reconciles the tracker with the latest store snapshot. Safe to call on every refresh or
    /// polled update — it only mutates when the store has something meaningful for the trip we're
    /// locked onto.
    func syncWithStore(_ store: PingStore) async {
        await syncWithSystemActivityState()
        walkMinutes = store.walkingMinutes

        if !isTracking, trackedDeparture != nil {
            // Live Activity was dismissed from outside the app. Clear the lock so the hero goes
            // back to planning instead of rendering a stale card forever.
            trackedDeparture = nil
            phase = .planning
            bufferSeconds = 0
            minutesUntilDeparture = nil
            hasSeededAlertState = false
            Self.clearPersistedTripID()
            return
        }

        if trackedDeparture == nil, isTracking,
            let persistedTripID = Self.loadPersistedTripID(),
            let found = Self.findDeparture(tripID: persistedTripID, in: store)
        {
            trackedDeparture = found
        }

        if let trackedTripID, let updated = Self.findDeparture(tripID: trackedTripID, in: store) {
            trackedDeparture = updated
        }

        if let tracked = trackedDeparture {
            let trigger = recomputePhase(for: tracked)
            await updateLiveActivity(for: tracked, store: store, trigger: trigger)

            // Clean up stale tracking: a Live Activity stuck on "Missed" for minutes is noise.
            // The in-app hero will fall back to planning mode (next catchable train) automatically.
            let secondsPastDeparture = Date().timeIntervalSince(tracked.effectiveDepartureTime)
            if phase == .missed, secondsPastDeparture >= 60 {
                await stop()
            }
        } else {
            phase = .planning
            bufferSeconds = 0
            minutesUntilDeparture = nil
        }
    }

    /// Locks the tracker onto `departure`, starts (or refreshes) the Live Activity, and persists
    /// the trip ID so tracking survives the app being backgrounded or killed.
    func start(departure: LiveDeparture, store: PingStore) async {
        walkMinutes = store.walkingMinutes
        trackedDeparture = departure
        Self.persistTripID(departure.tripID)
        // Seed the transition trackers so the first recompute after a fresh lock never fires
        // a backfill alert. The actual mutation happens inside recomputePhase.
        hasSeededAlertState = false
        _ = recomputePhase(for: departure)

        // While a trip is actively followed, the Live Activity is the alert channel. Cancel
        // any pending commute notifications so the user doesn't get a banner on top of the
        // Dynamic Island / Lock Screen Live Activity alert.
        await Self.cancelPendingCommuteNotifications()

        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        await syncWithSystemActivityState()
        let attrs = liveActivityAttributes(for: departure, store: store)
        let state = contentState(for: departure, store: store)

        if activity != nil {
            await activity?.update(.init(state: state, staleDate: nil))
            isTracking = true
            return
        }

        let requested = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        activity = requested
        isTracking = requested != nil
        #endif
    }

    /// Replaces the locked trip with the next catchable upcoming departure, or stops tracking if
    /// nothing viable is available. Used by the "Switch to next train" CTA.
    func switchToNextTrain(store: PingStore) async {
        let now = Date()
        let currentTripID = trackedTripID
        let candidate = store.upcomingDepartures.first { candidate in
            candidate.tripID != currentTripID && candidate.effectiveDepartureTime > now
        }

        if let candidate {
            await start(departure: candidate, store: store)
        } else {
            await stop()
        }
    }

    func stop() async {
        trackedDeparture = nil
        phase = .planning
        bufferSeconds = 0
        minutesUntilDeparture = nil
        hasSeededAlertState = false
        Self.clearPersistedTripID()
        #if canImport(ActivityKit)
        await syncWithSystemActivityState()
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        #endif
        isTracking = false
    }

    // MARK: - Private helpers

    /// Updates `phase` + `bufferSeconds` for `departure` and returns the Live Activity alert
    /// trigger — if any — that this tick crossed. The very first call after `start(...)` always
    /// returns `nil` (seed) so we don't fire backfill alerts when restoring a persisted trip.
    private func recomputePhase(for departure: LiveDeparture) -> AlertTrigger? {
        let now = Date()
        let untilDeparture = departure.effectiveDepartureTime.timeIntervalSince(now)
        let walkSeconds = TimeInterval(walkMinutes * 60)
        bufferSeconds = Int(untilDeparture - walkSeconds)

        if untilDeparture <= 0 {
            phase = .missed
        } else if walkSeconds - untilDeparture > 30 {
            // Can't reach the platform in time even if leaving now (30 s grace).
            phase = .likelyMissed
        } else {
            phase = .tracking
        }

        let freshMinutes = max(0, Int(ceil(untilDeparture / 60)))
        minutesUntilDeparture = freshMinutes
        // Bucket 0 = "leave now or behind", 1 = "still some slack".
        let bufferBucket = bufferSeconds < 30 ? 0 : 1

        defer {
            lastAlertPhase = phase
            lastAlertMinutesBucket = freshMinutes
            lastAlertBufferBucket = bufferBucket
            hasSeededAlertState = true
        }

        guard hasSeededAlertState else { return nil }

        if phase == .missed, lastAlertPhase != .missed {
            return .missed
        }
        if phase != .missed, bufferBucket == 0, lastAlertBufferBucket != 0 {
            return .leaveNow
        }
        if phase != .missed,
           freshMinutes <= 2,
           freshMinutes > 0,
           lastAlertMinutesBucket > 2,
           bufferBucket != 0
        {
            return .twoMinutes
        }
        return nil
    }

    private static func findDeparture(tripID: String, in store: PingStore) -> LiveDeparture? {
        if let next = store.nextDeparture, next.tripID == tripID {
            return next
        }
        return store.upcomingDepartures.first(where: { $0.tripID == tripID })
    }

    private static func persistTripID(_ tripID: String) {
        UserDefaults.standard.set(tripID, forKey: persistedTripIDKey)
    }

    private static func clearPersistedTripID() {
        UserDefaults.standard.removeObject(forKey: persistedTripIDKey)
    }

    private static func loadPersistedTripID() -> String? {
        UserDefaults.standard.string(forKey: persistedTripIDKey)
    }

    /// Cancels any pending scheduled commute notifications. Called when a Live Activity starts
    /// so the user only gets alerted through the activity's own sound/haptic instead of getting
    /// a duplicate banner on top. `NotificationScheduler.syncCommuteNotifications()` re-schedules
    /// on the next scene-phase change, so there's no permanent loss once tracking ends.
    private static func cancelPendingCommuteNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let commuteIDs = pending.map(\.identifier).filter { $0.hasPrefix("ping.commute.") }
        guard !commuteIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: commuteIDs)
    }

    #if canImport(ActivityKit)
    private func liveActivityAttributes(
        for departure: LiveDeparture,
        store: PingStore
    ) -> PingActivityAttributes {
        let destName = store.availableStops
            .first(where: { $0.id == departure.destinationStopID })?.name
            ?? departure.destinationStopID
        return PingActivityAttributes(destinationName: destName, lineName: store.selectedLine)
    }

    private func contentState(
        for departure: LiveDeparture,
        store: PingStore
    ) -> PingActivityAttributes.ContentState {
        let rideMin = max(
            1,
            Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded())
        )
        // Recompute the minutes countdown on every push. The static value on `LiveDeparture` is
        // captured at fetch time and never decrements, which would freeze the Live Activity.
        let untilDeparture = departure.effectiveDepartureTime.timeIntervalSince(Date())
        let freshMinutes = max(0, Int(ceil(untilDeparture / 60)))
        return PingActivityAttributes.ContentState(
            minutesUntilDeparture: freshMinutes,
            walkMinutes: walkMinutes,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime,
            phase: phase
        )
    }

    private func updateLiveActivity(
        for departure: LiveDeparture,
        store: PingStore,
        trigger: AlertTrigger? = nil
    ) async {
        guard isTracking else {
            return
        }
        let state = contentState(for: departure, store: store)
        let content = ActivityContent(state: state, staleDate: nil)
        if let alert = alertConfiguration(for: trigger, departure: departure) {
            await activity?.update(content, alertConfiguration: alert)
        } else {
            await activity?.update(content)
        }
    }

    private func alertConfiguration(
        for trigger: AlertTrigger?,
        departure: LiveDeparture
    ) -> AlertConfiguration? {
        guard let trigger else { return nil }
        let trainTime = departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened)
        switch trigger {
        case .leaveNow:
            return AlertConfiguration(
                title: "Leave now",
                body: "\(departure.trainLabel) · \(trainTime)",
                sound: .default
            )
        case .twoMinutes:
            return AlertConfiguration(
                title: "2 min to departure",
                body: "\(departure.trainLabel) · \(trainTime)",
                sound: .default
            )
        case .missed:
            return AlertConfiguration(
                title: "Missed \(departure.trainLabel)",
                body: "Open Ping to switch to the next train",
                sound: .default
            )
        }
    }
    #endif
}

// MARK: - Train hero card

private struct TrainHeroCard: View {
    let tracker: CommuteTracker
    let departure: LiveDeparture
    let onStartTracking: () -> Void
    let onStopTracking: () -> Void
    let onSwitchToNextTrain: () -> Void
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
    private var isTrackingThisTrip: Bool {
        tracker.isTrackingLocked && tracker.trackedTripID == departure.tripID
    }
    private var phase: TrackingPhase {
        isTrackingThisTrip ? tracker.phase : .planning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveActivityRow
            Divider().padding(.horizontal, 16)
            departureTimingHeader
            heroCountdown
            timelineSection
            if shouldShowStatusBanner {
                Divider().padding(.horizontal, 16)
                statusBanner
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

                HeroCountdownValue(targetDate: leaveByDate, phase: phase)
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

    private var shouldShowStatusBanner: Bool {
        switch phase {
        case .likelyMissed, .missed:
            true
        case .planning, .tracking:
            departure.isDelayed
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .likelyMissed:
            HStack(spacing: 8) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Cutting it close")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("Switch", action: onSwitchToNextTrain)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        case .missed:
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Missed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                Spacer(minLength: 8)
                Button("Switch to next", action: onSwitchToNextTrain)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        case .planning, .tracking:
            if departure.isDelayed {
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
        }
    }

    private var liveActivityRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isTrackingThisTrip ? "livephoto" : "sparkles")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 18)

            Text(isTrackingThisTrip ? "Following trip" : "Live Activity")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            if isTrackingThisTrip {
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
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            Text(CountdownFormatting.boardText(remainingSeconds: remainingSeconds))
        }
    }
}

private struct HeroCountdownValue: View {
    let targetDate: Date
    var phase: TrackingPhase = .planning

    /// Tint for the big countdown digits.
    ///
    /// We keep `.primary` for the neutral states so the number reads as "status quo, all good"
    /// and only escalate to orange/red when the tracker actually flags trouble. This lets the
    /// color itself carry the urgency signal without needing a separate animated border.
    private var digitColor: Color {
        switch phase {
        case .likelyMissed: .orange
        case .missed: .red
        case .planning, .tracking: .primary
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            let parts = CountdownFormatting.heroParts(remainingSeconds: remainingSeconds)

            if parts.isLongForm {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(digitColor)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(parts.trailingValue ?? "")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(digitColor)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.trailingUnit ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(digitColor)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .animation(.smooth(duration: 0.3), value: phase)
    }
}

// MARK: - Tracking haptics

/// Emits contextual haptic feedback as the tracked trip crosses meaningful thresholds.
///
/// * `.success` when the user locks onto a trip (*Follow trip*).
/// * `.impact(.heavy)` when slack first runs out — the "leave now" moment.
/// * `.warning` when the departure countdown first dips under 2 minutes while tracking.
/// * `.error` when the tracked trip transitions into `.missed`.
private struct TrackingHapticsModifier: ViewModifier {
    fileprivate enum LeaveNowBucket: Equatable { case idle, onTime, leaveNow }
    fileprivate enum TwoMinuteBucket: Equatable { case idle, above, underTwo }

    let tracker: CommuteTracker

    func body(content: Content) -> some View {
        content
            .modifier(RouteConfirmedHaptic(isTrackingLocked: tracker.isTrackingLocked))
            .modifier(LeaveNowHaptic(bucket: leaveNowBucket))
            .modifier(TwoMinuteHaptic(bucket: twoMinuteBucket))
            .modifier(MissedHaptic(phase: tracker.phase))
    }

    private var leaveNowBucket: LeaveNowBucket {
        guard tracker.isTrackingLocked else { return .idle }
        return tracker.bufferSeconds > 30 ? .onTime : .leaveNow
    }

    private var twoMinuteBucket: TwoMinuteBucket {
        guard tracker.isTrackingLocked, let minutes = tracker.minutesUntilDeparture else {
            return .idle
        }
        return minutes > 2 ? .above : .underTwo
    }
}

/// One-shot spring "bump" on the hero card when the leave-now threshold first trips.
///
/// Shares its transition detection logic with `TrackingHapticsModifier.leaveNowBucket` so the
/// visual beat lands in sync with the heavy haptic — user feels it and sees it at the same time.
/// Scale goes 1.0 → 1.03 → 1.0 via chained springs; we keep the amplitude small because the
/// hero card is already the largest element on screen and a bigger bump reads as gimmicky.
private struct LeaveNowBumpModifier: ViewModifier {
    let tracker: CommuteTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bumpScale: CGFloat = 1.0

    private var leaveNowBucket: TrackingHapticsModifier.LeaveNowBucket {
        guard tracker.isTrackingLocked else { return .idle }
        return tracker.bufferSeconds > 30 ? .onTime : .leaveNow
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(bumpScale)
            .onChange(of: leaveNowBucket) { oldValue, newValue in
                guard oldValue == .onTime, newValue == .leaveNow else { return }
                // Reduce Motion: keep the haptic (fired by TrackingHapticsModifier) but skip the
                // visual scale. No fallback flash — the existing phase-driven countdown color and
                // the status banner already carry the "you need to move" signal without motion.
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    bumpScale = 1.03
                } completion: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        bumpScale = 1.0
                    }
                }
            }
    }
}

private struct RouteConfirmedHaptic: ViewModifier {
    let isTrackingLocked: Bool

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .success,
            trigger: isTrackingLocked,
            condition: { oldValue, newValue in !oldValue && newValue }
        )
    }
}

private struct LeaveNowHaptic: ViewModifier {
    let bucket: TrackingHapticsModifier.LeaveNowBucket

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .impact(weight: .heavy),
            trigger: bucket,
            condition: { oldValue, newValue in oldValue == .onTime && newValue == .leaveNow }
        )
    }
}

private struct TwoMinuteHaptic: ViewModifier {
    let bucket: TrackingHapticsModifier.TwoMinuteBucket

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .warning,
            trigger: bucket,
            condition: { oldValue, newValue in oldValue == .above && newValue == .underTwo }
        )
    }
}

private struct MissedHaptic: ViewModifier {
    let phase: TrackingPhase

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .error,
            trigger: phase,
            condition: { oldValue, newValue in oldValue != .missed && newValue == .missed }
        )
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

private enum StationPickerTarget: String, Identifiable {
    case origin
    case destination

    var id: String {
        rawValue
    }
}

private struct StationPickerSheet: View {
    @Environment(PingStore.self) private var store
    let stops: [Stop]
    let title: String
    let counterpartStopID: StopID?
    let excludedStopIDs: Set<StopID>
    let onSelect: (Stop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var compatibleStopIDs: Set<StopID>?
    @State private var isLoadingCompatibility = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredStops: [Stop] {
        stops
            .filter { stop in
                let matchesQuery = trimmedQuery.isEmpty || stop.name.localizedStandardContains(trimmedQuery)
                let matchesCompatibility = compatibleStopIDs.map { $0.contains(stop.id) } ?? true
                let isNotExcluded = !excludedStopIDs.contains(stop.id)
                return matchesQuery && matchesCompatibility && isNotExcluded
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var nearbyStops: [Stop] {
        guard trimmedQuery.isEmpty, let userLocation = store.userLocation else {
            return []
        }

        let user = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        return filteredStops
            .compactMap { stop -> (Stop, CLLocationDistance)? in
                guard let coordinate = stop.coordinate else {
                    return nil
                }

                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: user)
                return (stop, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(3)
            .map(\.0)
    }

    var body: some View {
        List {
            if !nearbyStops.isEmpty {
                Section("Nearby Stations") {
                    ForEach(nearbyStops) { stop in
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

            if filteredStops.isEmpty && !trimmedQuery.isEmpty {
                Section {
                    Text("No compatible stations found for this route.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search station")
        .task {
            await refreshCompatibility()
        }
        .onChange(of: counterpartStopID) { _, _ in
            Task { await refreshCompatibility() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            if isLoadingCompatibility {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func refreshCompatibility() async {
        isLoadingCompatibility = true
        compatibleStopIDs = await store.compatibleStopIDs(with: counterpartStopID)
        isLoadingCompatibility = false
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

// MARK: - Service alerts sheet

/// Modal list of every *actionable* FGC alert, sorted by severity (most severe first).
///
/// `.info` alerts are filtered out entirely — they're announcements, not disruptions, and
/// including them makes the sheet feel noisy. Each row unpacks what the inline pill can only
/// summarize: full title, full details, affected line badges, and (when present) a validity
/// window.
private struct ServiceAlertsSheet: View {
    let alerts: [ServiceAlert]

    @Environment(\.dismiss) private var dismiss

    private var sortedAlerts: [ServiceAlert] {
        alerts
            .filter { $0.severity != .info }
            .sorted { lhs, rhs in
                let lRank = ServiceAlertPresentation.rank(for: lhs.severity)
                let rRank = ServiceAlertPresentation.rank(for: rhs.severity)
                if lRank != rRank { return lRank > rRank }
                // Stable tiebreaker so the list doesn't shuffle across refreshes.
                return lhs.id < rhs.id
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedAlerts.isEmpty {
                    ContentUnavailableView(
                        "No alerts",
                        systemImage: "checkmark.circle",
                        description: Text("FGC is not reporting any service alerts right now.")
                    )
                } else {
                    List {
                        ForEach(sortedAlerts) { alert in
                            ServiceAlertRow(alert: alert)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Service alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ServiceAlertRow: View {
    let alert: ServiceAlert

    var body: some View {
        let tint = ServiceAlertPresentation.color(for: alert.severity)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ServiceAlertPresentation.label(for: alert.severity).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint, in: Capsule())

                if !alert.affectedLines.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(alert.affectedLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let details = alert.details, !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let window = validityWindowLabel {
                Label(window, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Formats `startDate` / `endDate` into a short human-readable window, or `nil` when we
    /// have neither. Three shapes: both set (`"10:30 → 14:00"`, same-day short), start-only
    /// (`"From 10:30"`), end-only (`"Until 14:00"`).
    private var validityWindowLabel: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .short

        switch (alert.startDate, alert.endDate) {
        case (let start?, let end?):
            let calendar = Calendar.current
            if calendar.isDate(start, inSameDayAs: end) {
                return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
            }
            return "\(dayFormatter.string(from: start)) → \(dayFormatter.string(from: end))"
        case (let start?, nil):
            return "From \(dayFormatter.string(from: start))"
        case (nil, let end?):
            return "Until \(dayFormatter.string(from: end))"
        case (nil, nil):
            return nil
        }
    }
}
