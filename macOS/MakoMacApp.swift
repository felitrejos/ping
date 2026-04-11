import SwiftUI

@main
struct MakoMacApp: App {
    @State private var store = MacContainer.shared.store

    init() {
        MacContainer.shared.store.start()
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
                .frame(width: 340, height: 340)
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
