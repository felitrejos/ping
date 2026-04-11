import SwiftUI

public struct SharedSettingsView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserSettings.Keys.homeStationID) private var homeStationID = UserSettings.defaultHomeStationID
    @AppStorage(UserSettings.Keys.destinationStationID) private var destinationStationID = UserSettings.defaultDestinationStationID
    @AppStorage(UserSettings.Keys.walkingMinutes) private var walkingMinutes = UserSettings.defaultWalkingMinutes

    public init() {}

    public var body: some View {
        List {
            Section("Current setup") {
                LabeledContent("Origin") {
                    Text(stationName(for: homeStationID))
                        .foregroundStyle(UserSettings.isConfiguredStopID(homeStationID) ? .primary : .secondary)
                }

                LabeledContent("Destination") {
                    Text(stationName(for: destinationStationID))
                        .foregroundStyle(UserSettings.isConfiguredStopID(destinationStationID) ? .primary : .secondary)
                }

                LabeledContent("Walking time") {
                    Text("\(walkingMinutes) min")
                }

                LabeledContent("Calendar") {
                    Text(store.calendarAuthorization.isAuthorized ? "Allowed" : "Needs access")
                        .foregroundStyle(store.calendarAuthorization.isAuthorized ? .green : .secondary)
                }
            }

            Section("Route stations") {
                TextField(
                    "Search",
                    text: Binding(
                        get: { store.stopSearchText },
                        set: { store.stopSearchText = $0 }
                    )
                )

                if store.filteredStops.isEmpty {
                    Text("No stations found")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.filteredStops) { stop in
                    Menu {
                        Button {
                            homeStationID = stop.id
                            Task {
                                await store.setHomeStation(stop.id)
                            }
                        } label: {
                            Label("Set as origin", systemImage: "house.fill")
                        }

                        Button {
                            destinationStationID = stop.id
                            Task {
                                await store.setDestinationStation(stop.id)
                            }
                        } label: {
                            Label("Set as destination", systemImage: "mappin.and.ellipse")
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                Text(stop.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if homeStationID == stop.id {
                                Text("Origin")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if destinationStationID == stop.id {
                                Text("Destination")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Walking time") {
                Stepper(value: $walkingMinutes, in: 1 ... 20) {
                    Text("\(walkingMinutes) minutes")
                }
                .onChange(of: walkingMinutes) { _, newValue in
                    UserSettings.setWalkingMinutes(newValue)
                }
            }

            Section("Calendar") {
                Button("Request access") {
                    Task {
                        await store.requestCalendarAccess()
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func stationName(for stopID: StopID) -> String {
        guard UserSettings.isConfiguredStopID(stopID) else {
            return "Not selected"
        }

        return store.availableStops.first(where: { $0.id == stopID })?.name ?? stopID
    }
}
