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
                .frame(width: 420, height: 440)
        }
    }

    private var menuBarTitle: String {
        guard store.hasConfiguredRoute else {
            return "🚆 Setup"
        }

        if let dep = store.nextDeparture {
            let leaveIn = max(0, dep.minutesUntilDeparture - UserSettings.walkingMinutes())
            return "🚆 \(leaveIn) min"
        }
        return "🚆 --"
    }
}

@MainActor
enum MacContainer {
    static let shared = SharedContainer()
}
