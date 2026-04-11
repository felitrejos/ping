import BackgroundTasks
import SwiftUI

@main
struct MakoiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppContainer.shared.store
    @State private var notificationScheduler = AppContainer.shared.notificationScheduler

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    store.start()
                    notificationScheduler.registerBackgroundTasks()
                    await store.refresh()
                    await notificationScheduler.syncCommuteNotifications()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active || newPhase == .background else {
                        return
                    }
                    Task {
                        await store.refresh()
                        await notificationScheduler.syncCommuteNotifications()
                    }
                }
        }
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
