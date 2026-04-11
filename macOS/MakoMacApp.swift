import SwiftUI

@main
struct MakoMacApp: App {
    @State private var store = MacContainer.shared.store

    init() {
        let store = MacContainer.shared.store
        store.start()
        Task {
            await store.refresh()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Text(menuBarTitle)
        }

        Settings {
            SharedSettingsView()
                .environment(store)
                .frame(minWidth: 360, minHeight: 420)
        }
    }

    private var menuBarTitle: String {
        guard store.hasConfiguredRoute else {
            return "🚆 Setup"
        }

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
