import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct PingMacApp: App {
    @State private var store = MacContainer.shared.store
    @AppStorage(UserSettings.Keys.menuBarSleepMode) private var isMenuBarSleeping = false

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
        .menuBarExtraStyle(.window)

        Settings {
            SharedSettingsView()
                .environment(store)
                .frame(width: 420, height: 440)
                .onAppear {
                    #if os(macOS)
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    #endif
                }
                .onDisappear {
                    #if os(macOS)
                    NSApp.setActivationPolicy(.accessory)
                    #endif
                }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Ping") {
                    #if os(macOS)
                    NSApp.terminate(nil)
                    #endif
                }
                .keyboardShortcut("q")
            }
        }
    }

    private var menuBarTitle: String {
        guard store.hasConfiguredDefaultRoute else {
            return "🚆 Setup"
        }

        if isMenuBarSleeping {
            return "🚆💤"
        }

        if let dep = store.nextDeparture {
            let leaveIn = max(0, dep.minutesUntilDeparture - store.walkingMinutes)
            return "🚆 \(leaveIn) min"
        }
        return "🚆"
    }
}

@MainActor
enum MacContainer {
    static let shared = SharedContainer()
}
