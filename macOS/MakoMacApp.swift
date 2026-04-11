import SwiftUI

@main
struct MakoMacApp: App {
    @State private var store = MacContainer.shared.store

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .task {
                    store.start()
                    await store.refresh()
                }
        } label: {
            Text(menuBarTitle)
        }

        Settings {
            SharedSettingsView()
                .environment(store)
                .frame(minWidth: 360, minHeight: 420)
                .task {
                    store.start()
                    await store.refresh()
                }
        }
    }

    private var menuBarTitle: String {
        if let minutes = store.nextDeparture?.minutesUntilDeparture {
            return "🚆 \(minutes)"
        }
        return "🚆 --"
    }
}

@MainActor
enum MacContainer {
    static let shared = SharedContainer()
}
