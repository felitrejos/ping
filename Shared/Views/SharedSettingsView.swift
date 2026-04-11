import SwiftUI

public struct SharedSettingsView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserSettings.Keys.homeStationID) private var homeStationID = UserSettings.defaultHomeStationID
    @AppStorage(UserSettings.Keys.walkingMinutes) private var walkingMinutes = UserSettings.defaultWalkingMinutes

    public init() {}

    public var body: some View {
        List {
            Section("Home station") {
                TextField(
                    "Search",
                    text: Binding(
                        get: { store.stopSearchText },
                        set: { store.stopSearchText = $0 }
                    )
                )
                ForEach(store.filteredStops) { stop in
                    Button {
                        homeStationID = stop.id
                        Task {
                            await store.setHomeStation(stop.id)
                        }
                    } label: {
                        HStack {
                            Text(stop.name)
                            Spacer()
                            if homeStationID == stop.id {
                                Image(systemName: "checkmark")
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
                Text(store.calendarAuthorization.isAuthorized ? "Access granted" : "Access needed")
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
}
