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
            NavigationStack {
                SharedSettingsView()
            }
            .environment(store)
            .frame(minWidth: 420, minHeight: 460)
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
