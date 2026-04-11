import SwiftUI

public struct SharedSettingsView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserSettings.Keys.walkingMinutes) private var walkingMinutes = UserSettings.defaultWalkingMinutes
    @State private var selectedOrigin: StopID?
    @State private var selectedDestination: StopID?
    @State private var loaded = false

    public init() {}

    public var body: some View {
        Form {
            lineSection
            routeSection
            walkingSection
            calendarSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .toolbar(.hidden, for: .automatic)
        #endif
        .task {
            guard !loaded else { return }
            selectedOrigin = await store.selectedHomeStationID()
            selectedDestination = await store.selectedDestinationStationID()
            loaded = true
        }
    }

    private var lineSection: some View {
        Section {
            Picker(selection: Binding(
                get: { store.selectedLine },
                set: { store.selectedLine = $0 }
            )) {
                ForEach(store.availableLines, id: \.self) { line in
                    Text(line).tag(line)
                }
            } label: {
                Text("Line")
            }
            .pickerStyle(.menu)
        } header: {
            Text("FGC Line")
        }
    }

    private var routeSection: some View {
        Section {
            Picker(selection: $selectedOrigin) {
                Text("None").tag(StopID?.none)
                ForEach(store.lineStops) { stop in
                    Text(stop.name).tag(StopID?.some(stop.id))
                }
            } label: {
                Text("Origin")
            }
            .pickerStyle(.menu)
            .onChange(of: selectedOrigin) { _, newValue in
                Task { await store.setHomeStation(newValue) }
            }

            Picker(selection: $selectedDestination) {
                Text("None").tag(StopID?.none)
                ForEach(store.lineStops) { stop in
                    Text(stop.name).tag(StopID?.some(stop.id))
                }
            } label: {
                Text("Destination")
            }
            .pickerStyle(.menu)
            .onChange(of: selectedDestination) { _, newValue in
                Task { await store.setDestinationStation(newValue) }
            }
        } header: {
            Text("Route")
        } footer: {
            Text("Stations on the \(store.selectedLine) line.")
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
