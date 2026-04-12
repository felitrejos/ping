import SwiftUI

public struct SharedSettingsView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserSettings.Keys.autoSelectClosestOrigin) private var autoSelectClosestOrigin = false
    @State private var isFavoritePickerPresented = false

    #if os(macOS)
    @State private var originQuery = ""
    @State private var destinationQuery = ""
    @State private var originResults: [Stop] = []
    @State private var destinationResults: [Stop] = []
    @State private var isEditingOrigin = false
    @State private var isEditingDestination = false
    @State private var selectedOriginName: String?
    @State private var selectedDestinationName: String?
    @FocusState private var originFocused: Bool
    @FocusState private var destinationFocused: Bool
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
            FavoriteStationPickerView(
                availableStops: store.availableStops,
                favoriteStationIDs: Set(store.favoriteStationIDs),
                onSelect: { stop in
                    store.addFavoriteStation(stop.id)
                    isFavoritePickerPresented = false
                }
            )
        }
        #if os(macOS)
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
            stationInput(
                title: "Origin",
                placeholder: "Search station",
                query: $originQuery,
                results: $originResults,
                isEditing: $isEditingOrigin,
                focused: $originFocused,
                selectedName: $selectedOriginName,
                onClear: {
                    Task { await store.setHomeStation(nil) }
                }
            ) { stop in
                selectedOriginName = stop.name
                originQuery = stop.name
                originResults = []
                isEditingOrigin = false
                originFocused = false
                Task { await store.setHomeStation(stop.id) }
            }

            stationInput(
                title: "Destination",
                placeholder: "Search station",
                query: $destinationQuery,
                results: $destinationResults,
                isEditing: $isEditingDestination,
                focused: $destinationFocused,
                selectedName: $selectedDestinationName,
                onClear: {
                    Task { await store.setDestinationStation(nil) }
                }
            ) { stop in
                selectedDestinationName = stop.name
                destinationQuery = stop.name
                destinationResults = []
                isEditingDestination = false
                destinationFocused = false
                Task { await store.setDestinationStation(stop.id) }
            }

            if store.hasConfiguredDefaultRoute {
                Button(role: .destructive) {
                    clearRouteFields()
                    Task { await store.clearDefaultRoute() }
                } label: {
                    Label("Clear route", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Route")
        }
    }

    private func clearRouteFields() {
        originQuery = ""
        destinationQuery = ""
        selectedOriginName = nil
        selectedDestinationName = nil
        originResults = []
        destinationResults = []
        originFocused = false
        destinationFocused = false
        isEditingOrigin = false
        isEditingDestination = false
    }

    private func stationInput(
        title: String,
        placeholder: String,
        query: Binding<String>,
        results: Binding<[Stop]>,
        isEditing: Binding<Bool>,
        focused: FocusState<Bool>.Binding,
        selectedName: Binding<String?>,
        onClear: @escaping () -> Void,
        onSelect: @escaping (Stop) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            ZStack(alignment: .trailing) {
                TextField(placeholder, text: query)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .focused(focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .padding(.trailing, 28)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: query.wrappedValue) { _, newValue in
                        Task {
                            if newValue.isEmpty {
                                results.wrappedValue = []
                            } else {
                                results.wrappedValue = await store.searchStops(matching: newValue)
                            }
                        }
                    }
                    .onChange(of: focused.wrappedValue) { _, isFocused in
                        if isFocused {
                            isEditing.wrappedValue = true
                            if query.wrappedValue.isEmpty, let selectedName = selectedName.wrappedValue {
                                query.wrappedValue = selectedName
                            }
                        } else {
                            isEditing.wrappedValue = false
                            if let selectedName = selectedName.wrappedValue, query.wrappedValue != selectedName {
                                query.wrappedValue = selectedName
                            }
                        }
                    }

                if focused.wrappedValue && !query.wrappedValue.isEmpty {
                    Button {
                        query.wrappedValue = ""
                        selectedName.wrappedValue = nil
                        results.wrappedValue = []
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .padding(.trailing, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(title)")
                }
            }

            if isEditing.wrappedValue && !results.wrappedValue.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.wrappedValue.prefix(5)) { stop in
                        Button {
                            onSelect(stop)
                        } label: {
                            HStack {
                                Text(stop.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        if stop.id != results.wrappedValue.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func prefillStationNames(from stops: [Stop]) async {
        let originID = await store.selectedHomeStationID()
        let destinationID = await store.selectedDestinationStationID()

        if let originID, let name = stops.first(where: { $0.id == originID })?.name {
            selectedOriginName = name
            if !originFocused {
                originQuery = name
            }
        } else if !originFocused {
            selectedOriginName = nil
            originQuery = ""
        }

        if let destinationID, let name = stops.first(where: { $0.id == destinationID })?.name {
            selectedDestinationName = name
            if !destinationFocused {
                destinationQuery = name
            }
        } else if !destinationFocused {
            selectedDestinationName = nil
            destinationQuery = ""
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
                ForEach(store.favoriteStations) { stop in
                    HStack(spacing: 10) {
                        Text(stop.name)
                            .foregroundStyle(.primary)
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
                #if !os(macOS)
                .environment(\.editMode, .constant(.active))
                #endif
            }

            Button("Add new favorite") {
                isFavoritePickerPresented = true
            }
            .foregroundStyle(.blue)
        } header: {
            Text("Favorite stations")
        } footer: {
            Text("Tap favorite chips on Home to choose origin or destination.")
        }
    }

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

private struct FavoriteStationPickerView: View {
    let availableStops: [Stop]
    let favoriteStationIDs: Set<StopID>
    let onSelect: (Stop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredStops: [Stop] {
        availableStops
            .filter { !favoriteStationIDs.contains($0.id) }
            .filter { stop in
                query.isEmpty || stop.name.localizedStandardContains(query)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Stations") {
                    ForEach(filteredStops) { stop in
                        Button {
                            onSelect(stop)
                            dismiss()
                        } label: {
                            HStack {
                                Text(stop.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Favorite")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $query, prompt: Text("Search").bold())
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
#endif
            }
        }
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
