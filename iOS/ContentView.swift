import Combine
import CoreLocation
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Home tab

struct ContentView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var selectedOriginID: StopID?
    @State private var selectedOriginName: String?
    @State private var selectedDestinationID: StopID?
    @State private var selectedDestinationName: String?
    @State private var activeFavoritePopoverStopID: StopID?
    @State private var activeStationPicker: StationPickerTarget?
    @State private var routeSearchCommitted = false
    @State private var isSearchingRoute = false
    @State private var isServiceAlertsSheetPresented = false
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
                    title: target == .origin
                        ? String(localized: "Choose Origin")
                        : String(localized: "Choose Destination"),
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
        .onChange(of: store.availableStops) { _, stops in
            guard !stops.isEmpty else { return }
            Task { await prefillStationNames(from: stops) }
        }
        .onChange(of: store.lastUpdated) { _, _ in
            guard !store.availableStops.isEmpty else { return }
            Task { await prefillStationNames(from: store.availableStops) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Refresh the suggestion clock on foreground so a user who keeps the app open
            // across morning → evening sees the right card without waiting for the next tick.
            suggestionClock = Date()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            suggestionClock = date
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
        // Use separate singular/plural keys so localizers get the plural forms right — English's
        // trivial `+s` rule doesn't transfer to Catalan or Spanish agreement rules.
        let label: String
        if hasActionable {
            if actionable == 1 {
                label = String(localized: "FGC · \(actionable) alert", comment: "Status pill, singular form.")
            } else {
                label = String(localized: "FGC · \(actionable) alerts", comment: "Status pill, plural form.")
            }
        } else {
            label = String(localized: "FGC · All lines running")
        }

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
    /// Morning (05:00–11:59) + pending origin is not `homeStationID` + home is known
    /// → `"Start from home?"` sets pending origin to home.
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

        var title: String {
            switch self {
            case .startFromHome: String(localized: "Start from home?")
            }
        }

        var subtitle: String {
            switch self {
            case .startFromHome(_, let homeName):
                String(
                    localized: "Set \(homeName) as origin.",
                    comment: "Time-of-day suggestion subtitle. Placeholder is the home station name."
                )
            }
        }

        var actionLabel: String {
            switch self {
            case .startFromHome: String(localized: "Use home")
            }
        }

        var systemImage: String {
            switch self {
            case .startFromHome: "house.fill"
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
            return String(localized: "Searching...")
        }
        if !store.isLocationAccessGranted {
            return store.isLocationAccessDenied
                ? String(localized: "Open settings to enable location")
                : String(localized: "Enable location to search routes")
        }
        return String(localized: "Search routes")
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
        // Both `title` and `value` can be either a literal key ("ORIGIN", "Choose station")
        // or a runtime station name. `LocalizedStringKey` handles both: literals resolve to
        // their translations, station names miss the catalog and render verbatim.
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.caption2.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(value))
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
        // `value` is the raw (un-localized) fallback used in `stationPickerRow`. We branch on the
        // English source so the colour stays consistent regardless of language.
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
        if let raw = store.lastErrorMessage {
            // Surface the system error verbatim when there is something to read; otherwise fall
            // back to a friendlier explanation. The empty-string branch happens when an upstream
            // call fails without an associated message (e.g. a cancelled task), and shipping
            // an empty `NoticeCard` body makes the alert look broken.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty
                ? "Couldn't reach FGC. Check your connection — Ping will retry on the next refresh."
                : trimmed
            NoticeCard(
                title: "Couldn't refresh",
                message: message,
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
                    departure: displayed
                )
            } else {
                NoTrainsCard(onRefresh: {
                    Task { await store.refresh() }
                })
            }
        }
    }

    /// Departure shown at the top: the auto-rolling next catchable train.
    private var heroDeparture: LiveDeparture? {
        store.nextDeparture
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
                    targetDate: departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-store.walkingMinutes * 60))
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

            if isCurrentRoutePlan(plan) {
                Label("Matches current route", systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    applyCommutePlan(plan)
                } label: {
                    Label("Use this route", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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
            } else if !calendarPlans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(calendarPlans) { plan in
                        commuteRow(plan)
                    }
                }
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

    private var calendarPlans: [CommutePlan] {
        Array(store.commutePlans.prefix(5))
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
