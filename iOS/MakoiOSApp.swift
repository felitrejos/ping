import BackgroundTasks
import SwiftUI

@main
struct MakoiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppContainer.shared.store
    @State private var notificationScheduler = AppContainer.shared.notificationScheduler

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Home", systemImage: "tram.fill") }
                MapPlaceholderView()
                    .tabItem { Label("Map", systemImage: "map") }
                NavigationStack {
                    SharedSettingsView()
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environment(store)
            .task {
                store.start()
                notificationScheduler.registerBackgroundTasks()
                await store.refresh()
                await notificationScheduler.syncCommuteNotifications()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active || newPhase == .background else { return }
                Task {
                    await store.refresh()
                    await notificationScheduler.syncCommuteNotifications()
                }
            }
        }
    }
}

private struct MapPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Map coming soon", systemImage: "map")
    }
}

@MainActor
enum AppContainer {
    static let shared = IOSContainer()
}

@MainActor
final class IOSContainer {
    let shared = SharedContainer()
    lazy var notificationScheduler = NotificationScheduler(engine: shared.engine)

    var store: MakoStore {
        shared.store
    }
}
