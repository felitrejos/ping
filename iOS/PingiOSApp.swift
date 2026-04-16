import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications
#if canImport(AppIntents)
import AppIntents
#endif

@main
struct PingiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppContainer.shared.store
    @State private var notificationScheduler = AppContainer.shared.notificationScheduler
    @UIApplicationDelegateAdaptor(PingAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Home", systemImage: "tram.fill") }
                FGCMapView()
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
#if canImport(AppIntents)
                await PingIntentSupport.donateNextDepartureIntent()
#endif
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

@MainActor
enum AppContainer {
    static let shared = IOSContainer()
}

/// Registers as the `UNUserNotificationCenter` delegate so scheduled notifications still show
/// their banner + play their sound when the app is in the foreground (iOS suppresses banners
/// for the active app by default, which is wrong for commute alerts).
final class PingAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor
final class IOSContainer {
    let shared = SharedContainer()
    lazy var notificationScheduler = NotificationScheduler(engine: shared.engine)

    var store: PingStore {
        shared.store
    }
}
