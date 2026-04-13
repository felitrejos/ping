import SwiftUI

public struct SharedSettingsView: View {
    @Environment(PingStore.self) private var store
    @AppStorage(UserSettings.Keys.autoSelectClosestOrigin) private var autoSelectClosestOrigin = false
    @State private var isFavoritePickerPresented = false

    #if os(macOS)
    @State private var activeRoutePicker: RoutePickerTarget?
    @State private var selectedOriginName: String?
    @State private var selectedDestinationName: String?
    @State private var selectedFavoriteID: StopID?
    #endif

    public init() {}

    public var body: some View {
        Form {
            #if os(macOS)
            routeSection
            #endif
            favoritesSection
            originAutomationSection
            walkingSection
            calendarSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $isFavoritePickerPresented) {
            StationSearchPickerView(
                title: "Add Favorite",
                availableStops: store.availableStops,
                excludedStopIDs: Set(store.favoriteStationIDs),
                selectedStopID: nil
            ) { stop in
                store.addFavoriteStation(stop.id)
                isFavoritePickerPresented = false
            }
        }
        #if os(macOS)
        .sheet(item: $activeRoutePicker) { target in
            StationSearchPickerView(
                title: target.title,
                availableStops: store.availableStops,
                excludedStopIDs: [],
                selectedStopID: target == .origin ? store.homeStationID : store.destinationStationID
            ) { stop in
                applyRoutePickerSelection(stop: stop, target: target)
                activeRoutePicker = nil
            }
        }
        .toolbar(.hidden, for: .automatic)
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
        #endif
    }

    #if os(macOS)
    private var routeSection: some View {
        Section {
            routeSelectionButton(
                title: "Origin",
                value: selectedOriginName ?? "Choose station"
            ) {
                activeRoutePicker = .origin
            }

            routeSelectionButton(
                title: "Destination",
                value: selectedDestinationName ?? "Choose station"
            ) {
                activeRoutePicker = .destination
            }

            HStack(spacing: 8) {
                Button {
                    swapConfiguredRoute()
                } label: {
                    Label("Swap route", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!store.hasConfiguredDefaultRoute)

                if store.hasConfiguredDefaultRoute {
                    Button(role: .destructive) {
                        clearRouteSelection()
                        Task { await store.clearDefaultRoute() }
                    } label: {
                        Label("Clear route", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Route")
        } footer: {
            Text("Search and select stations using the pickers above.")
        }
    }

    private func routeSelectionButton(
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(value)
                        .lineLimit(1)
                        .foregroundStyle(value == "Choose station" ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func clearRouteSelection() {
        selectedOriginName = nil
        selectedDestinationName = nil
    }

    private func swapConfiguredRoute() {
        guard let originID = store.homeStationID, let destinationID = store.destinationStationID else {
            return
        }

        Task {
            await store.setRoute(origin: destinationID, destination: originID)
            await prefillStationNames(from: store.availableStops)
        }
    }

    private func applyRoutePickerSelection(stop: Stop, target: RoutePickerTarget) {
        switch target {
        case .origin:
            selectedOriginName = stop.name
            Task { await store.setHomeStation(stop.id) }
        case .destination:
            selectedDestinationName = stop.name
            Task { await store.setDestinationStation(stop.id) }
        }
    }

    private func prefillStationNames(from stops: [Stop]) async {
        let originID = await store.selectedHomeStationID()
        let destinationID = await store.selectedDestinationStationID()

        if let originID {
            selectedOriginName = stops.first(where: { $0.id == originID })?.name ?? originID
        } else {
            selectedOriginName = nil
        }

        if let destinationID {
            selectedDestinationName = stops.first(where: { $0.id == destinationID })?.name ?? destinationID
        } else {
            selectedDestinationName = nil
        }
    }
    #endif

    @ViewBuilder
    private var favoritesSection: some View {
        Section {
            if store.favoriteStations.isEmpty {
                Text("No favorites yet. Add stations you use most for quick switching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                #if os(macOS)
                List(selection: $selectedFavoriteID) {
                    ForEach(Array(store.favoriteStations.enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 10) {
                            Text(stop.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(favoriteDetailText(stop: stop, index: index))
                                .font(.body.weight(index == 0 ? .semibold : .regular))
                                .foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .tag(stop.id)
                    }
                    .onMove(perform: store.moveFavoriteStations(fromOffsets:toOffset:))
                }
                .frame(height: 190)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary)
                )

                HStack(spacing: 0) {
                    Button {
                        isFavoritePickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 24)

                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 2)

                    Button {
                        guard let selectedFavoriteID else { return }
                        store.removeFavoriteStation(selectedFavoriteID)
                        self.selectedFavoriteID = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 24)
                    .disabled(selectedFavoriteID == nil)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                #else
                ForEach(store.favoriteStations) { stop in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .foregroundStyle(.primary)
                            if stop.name == stop.id {
                                Text("Station metadata still loading")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            store.removeFavoriteStation(stop.id)
                        }
                    }
                }   
                .onMove(perform: store.moveFavoriteStations(fromOffsets:toOffset:))
                .environment(\.editMode, .constant(.active))
                #endif
            }

            #if !os(macOS)
            Button("Add new favorite") {
                isFavoritePickerPresented = true
            }
            .foregroundStyle(.blue)
            #endif
        } header: {
            Text("Favorite stations")
        } footer: {
            Text("Tip: Favorites show up in the menu bar for quick switching.")
        }
    }

    #if os(macOS)
    private func favoriteDetailText(stop: Stop, index: Int) -> String {
        if index == 0 {
            return "Primary"
        }
        return stop.id
    }
    #endif

    private var originAutomationSection: some View {
        Section {
            Toggle(isOn: $autoSelectClosestOrigin) {
                Label("Use closest station as origin", systemImage: "location.magnifyingglass")
            }
            .onChange(of: autoSelectClosestOrigin) { _, newValue in
                UserSettings.setAutoSelectClosestOrigin(newValue)
                store.resetClosestOriginSelectionForCurrentSession()
                if newValue {
                    store.requestLocationAccess()
                } else {
                    Task { await store.refresh() }
                }
            }

            Text("When enabled, Ping picks the nearest FGC station as your origin when the app starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Origin")
        }
    }

    private var walkingSection: some View {
        Section {
            if store.isUsingLiveLocation {
                LabeledContent {
                    Text("\(store.walkingMinutes) min")
                        .monospacedDigit()
                } label: {
                    Label("To station", systemImage: "location.fill")
                }
                Text("Based on your current location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.isLocationAccessDenied {
                Text("Location access is required to calculate walking time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(macOS)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.subheadline)
                #elseif canImport(UIKit) && !os(watchOS)
                OpenSettingsButton()
                    .font(.subheadline)
                #endif
            } else {
                if store.isLocationAccessGranted && !store.hasConfiguredRoute {
                    Text("Set an origin station to calculate walking time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enable location access to calculate walking time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Enable location access") {
                        store.requestLocationAccess()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            Text("Walking time")
        }
    }

    private var calendarSection: some View {
        Section {
            LabeledContent {
                switch store.calendarAuthorization {
                case .fullAccess, .authorized:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                case .notDetermined:
                    Button("Allow") {
                        Task { await store.requestCalendarAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                case .denied, .restricted:
                    Label("Denied", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                default:
                    Text(store.calendarAuthorization.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("Calendar access", systemImage: "calendar")
            }

            #if os(macOS)
            if store.calendarAuthorization == .denied || store.calendarAuthorization == .restricted {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.subheadline)
            }
            #elseif canImport(UIKit) && !os(watchOS)
            if store.calendarAuthorization == .denied || store.calendarAuthorization == .restricted {
                OpenSettingsButton()
                    .font(.subheadline)
            }
            #endif
        } header: {
            Text("Calendar")
        } footer: {
            Text("Ping uses your calendar to suggest when to leave for upcoming commutes.")
        }
    }
}

#if os(macOS)
private enum RoutePickerTarget: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin:
            "Choose Origin"
        case .destination:
            "Choose Destination"
        }
    }
}
#endif

private struct StationSearchPickerView: View {
    @Environment(PingStore.self) private var store
    let title: String
    let availableStops: [Stop]
    let excludedStopIDs: Set<StopID>
    let selectedStopID: StopID?
    let onSelect: (Stop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchResults: [Stop] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    private var uniqueAvailableStops: [Stop] {
        var seen = Set<StopID>()
        var result: [Stop] = []

        for stop in availableStops {
            if seen.contains(stop.id) {
                continue
            }
            seen.insert(stop.id)
            result.append(stop)
        }

        return result
    }

    private var displayedStops: [Stop] {
        let sourceStops: [Stop]
        if !searchResults.isEmpty || !query.isEmpty {
            sourceStops = searchResults
        } else {
            sourceStops = uniqueAvailableStops
        }

        return deduplicate(stops: sourceStops)
            .filter { !excludedStopIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var subtitleText: String {
        if isLoading {
            return "Searching stations..."
        }

        if displayedStops.isEmpty {
            return "No stations found"
        }

        return "\(displayedStops.count) stations"
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("Search and select a station")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                macSearchField
                    .frame(width: 230)
            }

            Group {
                if displayedStops.isEmpty && !isLoading {
                    ContentUnavailableView(
                        query.isEmpty ? "Stations unavailable" : "No matches",
                        systemImage: "magnifyingglass",
                        description: Text(query.isEmpty ? "Try again in a moment." : "Try another station name.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedStops) { stop in
                                Button {
                                    selectedStopIDForMac = stop.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(stop.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(stop.id)
                                            .foregroundStyle(.secondary)
                                        if stop.id == selectedStopIDForMac {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        stop.id == selectedStopIDForMac
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear
                                    )
                                }
                                .buttonStyle(.plain)

                                if stop.id != displayedStops.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary)
            )

            HStack(spacing: 8) {
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    applySelectedStop()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedStopIDForMac == nil)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .task {
            await performSearch(for: query)
            selectedStopIDForMac = selectedStopID
        }
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var macSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: Capsule())
    }

    @State private var selectedStopIDForMac: StopID?

    private func applySelectedStop() {
        guard let selectedStopIDForMac,
              let selectedStop = displayedStops.first(where: { $0.id == selectedStopIDForMac }) else {
            return
        }

        onSelect(selectedStop)
        dismiss()
    }
    #else
    private var iOSBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if displayedStops.isEmpty && !isLoading {
                    ContentUnavailableView(
                        query.isEmpty ? "Stations unavailable" : "No matches",
                        systemImage: "magnifyingglass",
                        description: Text(query.isEmpty ? "Pull to retry or try again in a moment." : "Try a different station name.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Stations") {
                            ForEach(displayedStops) { stop in
                                Button {
                                    onSelect(stop)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(stop.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if stop.id == selectedStopID {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitleText)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $query, prompt: Text("Search stations"))
            .task {
                await performSearch(for: query)
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Retry") {
                        Task { await performSearch(for: query) }
                    }
                }
            }
        }
    }
    #endif

    private func deduplicate(stops: [Stop]) -> [Stop] {
        var seen = Set<StopID>()
        var deduped: [Stop] = []

        for stop in stops {
            if seen.insert(stop.id).inserted {
                deduped.append(stop)
            }
        }

        return deduped
    }

    private func scheduleSearch(for newValue: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await performSearch(for: newValue)
        }
    }

    private func performSearch(for term: String) async {
        isLoading = true
        let fetched = await store.searchStops(matching: term)
        searchResults = fetched
        #if os(macOS)
        if let selectedStopIDForMac, !searchResults.contains(where: { $0.id == selectedStopIDForMac }) {
            self.selectedStopIDForMac = nil
        }
        #endif
        isLoading = false
    }
}

#if canImport(UIKit) && !os(watchOS)
private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}
#endif
