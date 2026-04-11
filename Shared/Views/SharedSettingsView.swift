import SwiftUI

public struct SharedSettingsView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserSettings.Keys.walkingMinutes) private var walkingMinutes = UserSettings.defaultWalkingMinutes
    @State private var originName: String?
    @State private var destinationName: String?
    @State private var pickerTarget: StationPickerTarget?

    public init() {}

    public var body: some View {
        Form {
            routeSection
            walkingSection
            calendarSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task {
            await loadStationNames()
        }
        .sheet(item: $pickerTarget) { target in
            NavigationStack {
                StationPickerView(target: target) { stop in
                    Task {
                        await selectStation(stop, for: target)
                    }
                    pickerTarget = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var routeSection: some View {
        Section {
            Button {
                pickerTarget = .origin
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(originName ?? "Choose")
                            .foregroundStyle(originName != nil ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                } label: {
                    Label("Origin", systemImage: "house")
                }
            }
            .tint(.primary)

            Button {
                pickerTarget = .destination
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(destinationName ?? "Choose")
                            .foregroundStyle(destinationName != nil ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                } label: {
                    Label("Destination", systemImage: "mappin.and.ellipse")
                }
            }
            .tint(.primary)
        } header: {
            Text("Route")
        }
    }

    private var walkingSection: some View {
        Section {
            Stepper(value: $walkingMinutes, in: 1...30) {
                LabeledContent {
                    Text("\(walkingMinutes) min")
                        .monospacedDigit()
                } label: {
                    Label("To station", systemImage: "figure.walk")
                }
            }
            .onChange(of: walkingMinutes) { _, newValue in
                UserSettings.setWalkingMinutes(newValue)
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
            Text("Mako uses your calendar to suggest when to leave for upcoming commutes.")
        }
    }

    private func loadStationNames() async {
        let stops = store.availableStops
        let homeID = await store.selectedHomeStationID()
        let destID = await store.selectedDestinationStationID()
        originName = stops.first(where: { $0.id == homeID })?.name
        destinationName = stops.first(where: { $0.id == destID })?.name
    }

    private func selectStation(_ stop: Stop, for target: StationPickerTarget) async {
        switch target {
        case .origin:
            originName = stop.name
            await store.setHomeStation(stop.id)
        case .destination:
            destinationName = stop.name
            await store.setDestinationStation(stop.id)
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

enum StationPickerTarget: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin: "Choose Origin"
        case .destination: "Choose Destination"
        }
    }
}

struct StationPickerView: View {
    let target: StationPickerTarget
    let onSelect: (Stop) -> Void

    @Environment(MakoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List(filtered) { stop in
            Button {
                onSelect(stop)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name)
                    Text(stop.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
        .searchable(text: $searchText, prompt: "Station name")
        .navigationTitle(target.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var filtered: [Stop] {
        guard !searchText.isEmpty else {
            return store.availableStops
        }
        return store.availableStops.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
